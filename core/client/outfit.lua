
gg = gg or {}

local RESOURCE = GetCurrentResourceName()

local MODELS = {
    male   = "mp_m_freemode_01",
    female = "mp_f_freemode_01",
}

local COMPONENTS = {
    face = 0, mask = 1, hair = 2, arms = 3, pants = 4, bag = 5,
    shoes = 6, accessory = 7, undershirt = 8, kevlar = 9, badge = 10, jacket = 11,
}

local PROPS = {
    hat = 0, glasses = 1, ear = 2, watch = 6, bracelet = 7,
}

local LOAD_TIMEOUT_MS = 8000

local DISTANCE = { min = 1.0, max = 5.0 }
local HEIGHT   = { min = 0.1, max = 2.2 }

local preview = nil
local camera  = nil
local heading = 0.0

local START_DISTANCE = 3.1
local START_HEIGHT   = 0.62

local view = { dir = nil, at = nil, distance = START_DISTANCE, height = START_HEIGHT }

local SHIFT_RATIO = 0.18

local target = { distance = START_DISTANCE, height = START_HEIGHT }

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end

    return value
end

local hidden = false

local function hidePlayer(on)
    if on == hidden then return end

    hidden = on

    local ped = PlayerPedId()

    SetEntityVisible(ped, not on, false)
    SetLocalPlayerVisibleLocally(not on)
    FreezeEntityPosition(ped, on)
    SetEntityInvincible(ped, on)
end

local BLOCKED = {
    24,  -- attack
    25,  -- aim
    140, -- melee light
    141, -- melee heavy
    142, -- melee alternate
    257, -- attack 2
    263, -- melee attack 1
    264, -- melee attack 2
    45,  -- reload
    22,  -- jump
    23,  -- enter vehicle
    75,  -- exit vehicle
    199, -- pause
    200, -- pause, alternate
}

local blocking = false

local function blockInput(on)
    if on == blocking then return end

    blocking = on

    if not on then return end

    CreateThread(function()
        while blocking do
            for index = 1, #BLOCKED do
                DisableControlAction(0, BLOCKED[index], true)
            end

            if IsPauseMenuActive() then SetPauseMenuActive(false) end

            Wait(0)
        end
    end)
end

local function applyCamera()
    if not (camera and view.at and view.dir) then return end

    SetCamCoord(
        camera,
        view.at.x + (view.dir.x * view.distance),
        view.at.y + (view.dir.y * view.distance),
        view.at.z + view.height
    )

    local rx, ry = -view.dir.y, view.dir.x

    local shift = view.distance * SHIFT_RATIO

    PointCamAtCoord(
        camera,
        view.at.x + (rx * shift),
        view.at.y + (ry * shift),
        view.at.z + (view.height * 0.85) + 0.15
    )
end

local easing = false

local function ease()
    if easing then return end

    easing = true

    CreateThread(function()
        while camera do
            local dd = target.distance - view.distance
            local dh = target.height - view.height

            if math.abs(dd) < 0.002 and math.abs(dh) < 0.002 then
                view.distance, view.height = target.distance, target.height

                applyCamera()

                break
            end

            view.distance = view.distance + (dd * 0.16)
            view.height   = view.height + (dh * 0.16)

            applyCamera()

            Wait(0)
        end

        easing = false
    end)
end

local function frame(ped)
    view.at = GetEntityCoords(ped)

    if not view.dir then
        local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)

        local dx, dy = front.x - view.at.x, front.y - view.at.y
        local length = math.sqrt((dx * dx) + (dy * dy))

        if length < 0.001 then length = 1.0 end

        view.dir = { x = dx / length, y = dy / length }
    end

    if camera then
        applyCamera()

        return
    end

    camera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", view.at.x, view.at.y, view.at.z + 1.0, 0.0, 0.0, 0.0, 40.0, false, 0)

    applyCamera()

    SetCamActive(camera, true)
    RenderScriptCams(true, true, 400, true, true)
end

local base = nil

local function clearPed()
    if preview and DoesEntityExist(preview) then DeleteEntity(preview) end

    preview = nil
    base    = nil
end

local function clear()
    if camera then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(camera, false)

        camera = nil
    end

    clearPed()

    view.dir = nil
    view.at  = nil

    view.distance, target.distance = START_DISTANCE, START_DISTANCE
    view.height, target.height     = START_HEIGHT, START_HEIGHT

    hidePlayer(false)
    blockInput(false)
end

local function makeBase(ped, gender)
    SetPedDefaultComponentVariation(ped)

    local shape = gender == "female" and 21 or 4

    SetPedHeadBlendData(ped, shape, shape, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)

    SetPedHairColor(ped, 1, 1)

    local components, props = {}, {}

    for name, id in pairs(COMPONENTS) do
        components[name] = { drawable = GetPedDrawableVariation(ped, id), texture = GetPedTextureVariation(ped, id) }
    end

    for name, id in pairs(PROPS) do
        props[name] = { drawable = GetPedPropIndex(ped, id), texture = GetPedPropTextureIndex(ped, id) }
    end

    base = { components = components, props = props }
end

local function limitsOf(ped)
    local components, props = {}, {}

    for name, id in pairs(COMPONENTS) do
        local drawables = GetNumberOfPedDrawableVariations(ped, id)
        local current   = GetPedDrawableVariation(ped, id)

        components[name] = {
            drawable = math.max(0, drawables - 1),
            texture  = math.max(0, GetNumberOfPedTextureVariations(ped, id, current) - 1),
        }
    end

    for name, id in pairs(PROPS) do
        local drawables = GetNumberOfPedPropDrawableVariations(ped, id)
        local current   = GetPedPropIndex(ped, id)

        props[name] = {
            drawable = math.max(-1, drawables - 1),
            texture  = current >= 0 and math.max(0, GetNumberOfPedPropTextureVariations(ped, id, current) - 1) or 0,
        }
    end

    return { components = components, props = props }
end

local function apply(ped, slots, ids, isProp, fallback)
    for name, id in pairs(ids) do
        local slot     = type(slots) == "table" and slots[name] or nil
        local drawable = slot and tonumber(slot.drawable)
        local texture  = slot and tonumber(slot.texture) or 0

        if drawable == nil then
            local was = (fallback or {})[name] or {}

            drawable = was.drawable or (isProp and -1 or 0)
            texture  = was.texture or 0
        end

        if isProp then
            if drawable < 0 then
                ClearPedProp(ped, id)
            else
                SetPedPropIndex(ped, id, drawable, texture, true)
            end
        else
            SetPedComponentVariation(ped, id, drawable, texture, 0)
        end
    end
end

local function spawn(gender)
    local hash = joaat(MODELS[gender] or MODELS.male)

    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    local player = PlayerPedId()
    local at     = GetOffsetFromEntityInWorldCoords(player, 0.0, 2.2, 0.0)

    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z + 1.0, false)

    local ped = CreatePed(4, hash, at.x, at.y, (found and groundZ or at.z) + 0.02, 0.0, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(ped) then return nil end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityAsMissionEntity(ped, true, true)

    heading = (GetEntityHeading(player) + 180.0) % 360.0

    SetEntityHeading(ped, heading)

    return ped
end

RegisterNUICallback("outfit_preview", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    local gender = data.gender == "female" and "female" or "male"

    CreateThread(function()
        local model = joaat(MODELS[gender])

        if preview and DoesEntityExist(preview) and GetEntityModel(preview) ~= model then clearPed() end

        if not (preview and DoesEntityExist(preview)) then
            preview = spawn(gender)

            if not preview then return end

            makeBase(preview, gender)

            hidePlayer(true)
            blockInput(true)
        end

        apply(preview, data.components, COMPONENTS, false, (base or {}).components)
        apply(preview, data.props, PROPS, true, (base or {}).props)

        SetPedHairColor(preview, 1, 1)

        frame(preview)

        SendNUIMessage({ action = "outfit_limits", data = limitsOf(preview) })
    end)
end)

RegisterNUICallback("outfit_close", function(_, cb)
    cb({ ok = true })

    clear()
end)

RegisterNUICallback("outfit_focus", function(_, cb)
    cb({ ok = true })

    SetNuiFocus(true, true)
end)

RegisterNUICallback("outfit_turn", function(data, cb)
    cb({ ok = true })

    if not (preview and DoesEntityExist(preview)) then return end

    heading = (heading + (tonumber(data and data.by) or 0.0)) % 360.0

    SetEntityHeading(preview, heading)
end)

RegisterNUICallback("outfit_camera", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    target.distance = clamp(target.distance + (tonumber(data.dolly) or 0.0), DISTANCE.min, DISTANCE.max)
    target.height   = clamp(target.height + (tonumber(data.rise) or 0.0), HEIGHT.min, HEIGHT.max)

    ease()
end)

AddEventHandler("onResourceStop", function(name)
    if name == RESOURCE then clear() end
end)

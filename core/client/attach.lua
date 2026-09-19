
local RESOURCE = GetCurrentResourceName()

GG_EDITOR_STAGE = GG_EDITOR_STAGE or {}

GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }
GG_EDITOR_BUCKET.enter = GG_EDITOR_BUCKET.enter or function() return false end
GG_EDITOR_BUCKET.leave = GG_EDITOR_BUCKET.leave or function() end

local PLACEHOLDER_KIT = {
    id    = "__placeholder",
    label = "Placeholder (Cone)",
    props = { { model = "prop_roadcone02a", offset = { x = 0.0, y = 0.0, z = 0.0 } } },
}

local LOAD_TIMEOUT_MS = 8000

local ROT_ORDER = 2

local open = false
local hadFocus = false

local prop = nil
local home = nil   -- where the ped was before it was borrowed

local state = {
    subject = "prop",       -- "prop" | "ped"
    target  = "ped",        -- "ped" | "vehicle" | "prop"
    anchor  = "",           -- anchor prop model, while the target is a prop
    alive   = true,         -- a subject ped: on its feet, or a body

    flags   = {
        frozen      = true,
        noCollision = true,
        blockEvents = true,
        invincible  = true,
        noTarget    = true,
        noRagdoll   = true,
    },
    anim    = { dict = "", name = "" },  -- what the subject ped is doing
    model   = "",
    bone    = 57005,        -- ped bone id
    boneName = "chassis",   -- vehicle bone name
    vehicle = "taxi",
    ped     = "",           -- test ped model, empty while wearing your own
    pos     = { x = 0.0, y = 0.0, z = 0.0 },
    rot     = { x = 0.0, y = 0.0, z = 0.0 },
}

local testCar = nil
local anchorProp = nil

local job = nil

local followers = {}

local function say(message)
    print(("[gg_lib] %s"):format(message))
end

local function fault(message, ...)
    say(("placement: " .. message):format(...))
end

local BLOCKED = {
    24, 25, 257, 263, 264,
    140, 141, 142, 143,
    69, 70, 92, 114, 331,
    37, 245, 199, 200,
    19,
}

local LOOK_KEY = 19            -- left alt

local cursor = true

local function setCursor(on)
    cursor = on

    SetNuiFocus(on, on)

    SendNUIMessage({ action = "attach_look", data = { LOOKING = not on } })
end

local function watchCursor()
    CreateThread(function()
        while open do
            if not cursor and IsDisabledControlJustPressed(0, LOOK_KEY) then
                setCursor(true)
            end

            if not cursor then
                for index = 1, #BLOCKED do
                    DisableControlAction(0, BLOCKED[index], true)
                end
            end

            Wait(0)
        end

        cursor = true
    end)
end

local function targetEntity()
    if state.target == "vehicle" and testCar and DoesEntityExist(testCar) then return testCar end
    if state.target == "prop" and anchorProp and DoesEntityExist(anchorProp) then return anchorProp end

    return PlayerPedId()
end

local function boneIndex()
    local entity = targetEntity()

    if state.target == "prop" then return 0 end

    if state.target == "vehicle" then
        local index = GetEntityBoneIndexByName(entity, state.boneName)

        return index
    end

    if state.bone == 0 then return 0 end

    return GetPedBoneIndex(entity, state.bone)
end

local frame = nil   -- { origin, right, forward, up }

local prop_centre = { x = 0.0, y = 0.0, z = 0.0 }

local function sub(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a, b)
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end

    return value
end

local function measureFrame()
    if not (prop and DoesEntityExist(prop)) then return end

    AttachEntityToEntity(
        prop, targetEntity(), boneIndex(),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        true, true, false, true, ROT_ORDER, true
    )

    Wait(0)

    local origin = GetEntityCoords(prop)

    frame = {
        origin  = origin,
        right   = sub(GetOffsetFromEntityInWorldCoords(prop, 1.0, 0.0, 0.0), origin),
        forward = sub(GetOffsetFromEntityInWorldCoords(prop, 0.0, 1.0, 0.0), origin),
        up      = sub(GetOffsetFromEntityInWorldCoords(prop, 0.0, 0.0, 1.0), origin),
    }
end

local function toBoneSpace(at, right, forward, up)
    if not frame then return nil, nil end

    local delta = sub(at, frame.origin)

    local pos = {
        x = dot(delta, frame.right),
        y = dot(delta, frame.forward),
        z = dot(delta, frame.up),
    }

    local lr = { x = dot(right, frame.right),   y = dot(right, frame.forward),   z = dot(right, frame.up) }
    local lf = { x = dot(forward, frame.right), y = dot(forward, frame.forward), z = dot(forward, frame.up) }
    local lu = { x = dot(up, frame.right),      y = dot(up, frame.forward),      z = dot(up, frame.up) }

    local rot = {
        x = math.deg(math.asin(clamp(lf.z, -1.0, 1.0))),
        y = math.deg(math.atan(-lr.z, lu.z)),
        z = math.deg(math.atan(-lf.x, lf.y)),
    }

    return pos, rot
end

local function modelCentre(hash)
    local minimum, maximum = GetModelDimensions(hash)

    if not minimum or not maximum then return { x = 0.0, y = 0.0, z = 0.0 } end

    return {
        x = (minimum.x + maximum.x) * 0.5,
        y = (minimum.y + maximum.y) * 0.5,
        z = (minimum.z + maximum.z) * 0.5,
    }
end

local function clearFollowers()
    for index = 1, #followers do
        if DoesEntityExist(followers[index]) then DeleteEntity(followers[index]) end
    end

    followers = {}
end

local function clearProp()
    clearFollowers()

    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end

    prop = nil
    prop_centre = { x = 0.0, y = 0.0, z = 0.0 }
end

local function reattach()
    if not (prop and DoesEntityExist(prop)) then return end

    AttachEntityToEntity(
        prop, targetEntity(), boneIndex(),
        state.pos.x, state.pos.y, state.pos.z,
        state.rot.x, state.rot.y, state.rot.z,
        true, true, false, true, ROT_ORDER, true
    )
end

local function publishProp()
    if not (prop and DoesEntityExist(prop)) then
        SendNUIMessage({ action = "attach_prop", data = { PLACED = false } })
        return
    end

    local origin = GetEntityCoords(prop)

    local at = GetOffsetFromEntityInWorldCoords(prop, prop_centre.x, prop_centre.y, prop_centre.z)

    SendNUIMessage({
        action = "attach_prop",
        data   = {
            PLACED  = true,
            AT      = at,
            RIGHT   = sub(GetOffsetFromEntityInWorldCoords(prop, 1.0, 0.0, 0.0), origin),
            FORWARD = sub(GetOffsetFromEntityInWorldCoords(prop, 0.0, 1.0, 0.0), origin),
            UP      = sub(GetOffsetFromEntityInWorldCoords(prop, 0.0, 0.0, 1.0), origin),
            POS     = state.pos,
            ROT     = state.rot,
            BONE_OK = boneIndex() ~= -1,
        },
    })
end

local function rebuild()
    measureFrame()
    reattach()

    Wait(0)

    publishProp()
end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

local function attachFollowers()
    clearFollowers()

    if not (prop and DoesEntityExist(prop)) then return end
    if not job or type(job.props) ~= "table" or #job.props < 2 then return end

    local base = job.props[1].offset or {}

    for index = 2, #job.props do
        local spec = job.props[index]
        local hash = joaat(spec.model or "")

        if loadModel(hash) then
            local at = GetEntityCoords(prop)
            local extra = CreateObject(hash, at.x, at.y, at.z, false, false, false)

            SetModelAsNoLongerNeeded(hash)

            if extra and DoesEntityExist(extra) then
                local offset = spec.offset or {}
                local rotation = spec.rotation or {}

                AttachEntityToEntity(
                    extra, prop, 0,
                    (tonumber(offset.x) or 0.0) - (tonumber(base.x) or 0.0),
                    (tonumber(offset.y) or 0.0) - (tonumber(base.y) or 0.0),
                    (tonumber(offset.z) or 0.0) - (tonumber(base.z) or 0.0),
                    tonumber(rotation.x) or 0.0,
                    tonumber(rotation.y) or 0.0,
                    tonumber(rotation.z) or 0.0,
                    true, true, false, false, ROT_ORDER, true
                )

                followers[#followers + 1] = extra
            end
        else
            say(("kit prop '%s' would not load"):format(tostring(spec.model)))
        end
    end
end

local function playOn(entity, dict, name)
    if type(dict) ~= "string" or dict == "" or type(name) ~= "string" or name == "" then return false end
    if not DoesEntityExist(entity) then return false end

    RequestAnimDict(dict)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then
            say(("animation dictionary '%s' would not load"):format(dict))

            return false
        end

        Wait(0)
    end

    TaskPlayAnim(entity, dict, name, 8.0, -8.0, -1, 1, 0.0, false, false, false)

    return true
end

local function applyFlags(ped)
    if not (ped and DoesEntityExist(ped)) then return end

    local flags = state.flags

    FreezeEntityPosition(ped, flags.frozen == true)

    SetEntityCollision(ped, flags.noCollision ~= true, false)

    SetBlockingOfNonTemporaryEvents(ped, flags.blockEvents == true)
    SetEntityInvincible(ped, flags.invincible == true)
    SetPedSuffersCriticalHits(ped, flags.invincible ~= true)
    SetPedCanBeTargetted(ped, flags.noTarget ~= true)
    SetPedCanRagdoll(ped, flags.noRagdoll ~= true)
end

local function dressSubjectPed(ped)
    applyFlags(ped)

    if state.alive then
        playOn(ped, state.anim.dict, state.anim.name)

        return
    end

    SetEntityHealth(ped, 0)
end

local function createSubject(hash)
    local at = GetEntityCoords(PlayerPedId())

    if state.subject == "ped" then
        if not IsModelAPed(hash) then return nil, "not a ped model" end

        local ped = CreatePed(4, hash, at.x, at.y, at.z, 0.0, false, false)

        if not (ped and DoesEntityExist(ped)) then return nil, "would not spawn" end

        dressSubjectPed(ped)

        return ped
    end

    local object = CreateObject(hash, at.x, at.y, at.z, false, false, false)

    if not (object and DoesEntityExist(object)) then return nil, "would not spawn" end

    return object
end

local function spawn(model)
    clearProp()

    if type(model) ~= "string" or model == "" then
        fault("asked to spawn a %s, not a model name", type(model))

        return false
    end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        say(("%s model '%s' is not in the game"):format(state.subject, model))

        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            say(("%s model '%s' would not load"):format(state.subject, model))

            SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

            return false
        end

        Wait(0)
    end

    local made, why = createSubject(hash)

    SetModelAsNoLongerNeeded(hash)

    if not made then
        say(("%s '%s' %s"):format(state.subject, model, tostring(why)))

        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    prop = made

    state.model = model
    prop_centre = modelCentre(hash)

    measureFrame()
    reattach()

    Wait(0)

    publishProp()

    SendNUIMessage({ action = "attach_state", data = { MODEL = model, ERROR = false } })

    return true
end

local function paintVehicle(vehicle, color)
    if type(color) ~= "table" then return end

    local primary, secondary = color.primary, color.secondary

    if primary == nil and secondary == nil then return end

    SetVehicleColours(vehicle, math.floor(tonumber(primary) or 0), math.floor(tonumber(secondary) or 0))

    if type(primary) ~= "table" and type(secondary) ~= "table" then return end

    SetVehicleModKit(vehicle, 0)

    if type(primary) == "table" then
        SetVehicleCustomPrimaryColour(vehicle, primary.r or 0, primary.g or 0, primary.b or 0)
    end

    if type(secondary) == "table" then
        SetVehicleCustomSecondaryColour(vehicle, secondary.r or 0, secondary.g or 0, secondary.b or 0)
    end
end
local function clearCar()
    if testCar and DoesEntityExist(testCar) then DeleteEntity(testCar) end

    testCar = nil
end

local function spawnCar(model)
    clearCar()

    local vehicle, why = GG_EDITOR_STAGE.spawn(model)

    if not vehicle then
        say(tostring(why))

        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    testCar = vehicle

    local look = job and job.properties

    if type(look) == "table" and next(look) then
        local dressed, why = pcall(GGVehicle.setProperties, testCar, look)

        if not dressed then fault("could not dress %s: %s", tostring(model), tostring(why)) end
    else
        paintVehicle(testCar, job and job.color)
    end

    state.vehicle = model

    return true
end

local function ride()
    return GG_EDITOR_STAGE.ride(testCar)
end

local function clearAnchor()
    if anchorProp and DoesEntityExist(anchorProp) then DeleteEntity(anchorProp) end

    anchorProp = nil
end

local function spawnAnchor(model)
    clearAnchor()

    if type(model) ~= "string" or model == "" then return false end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        say(("anchor model '%s' is not in the game"):format(model))

        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    if not loadModel(hash) then
        say(("anchor model '%s' would not load"):format(model))

        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    local ahead = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 1.6, 0.0)

    anchorProp = CreateObject(hash, ahead.x, ahead.y, ahead.z, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not (anchorProp and DoesEntityExist(anchorProp)) then
        SendNUIMessage({ action = "attach_state", data = { ERROR = model } })

        return false
    end

    PlaceObjectOnGroundProperly(anchorProp)
    FreezeEntityPosition(anchorProp, true)

    state.anchor = model

    return true
end

local ownPed = nil

local function try(fn, ...)
    if type(fn) ~= "function" then return nil end

    local ok, value = pcall(fn, ...)

    if ok then return value end

    return nil
end

local function native(...)
    for _, name in ipairs({ ... }) do
        local fn = _G[name]

        if type(fn) == "function" then return fn end
    end

    return nil
end

local getHairColour  = native("GetPedHairColor", "GetPedHairColour")
local getHairHigh    = native("GetPedHairHighlightColor", "GetPedHairHighlightColour")
local getEyeColour   = native("GetPedEyeColor", "GetPedEyeColour")
local getFaceFeature = native("GetPedFaceFeature", "_GetPedFaceFeature")

local setHairColour  = native("SetPedHairColor", "SetPedHairColour")
local setEyeColour   = native("SetPedEyeColor", "SetPedEyeColour")
local setOverlayHue  = native("SetPedHeadOverlayColor", "SetPedHeadOverlayColour")

local function snapshotPed()
    if ownPed then return end

    local ped = PlayerPedId()

    local shot = {
        model      = GetEntityModel(ped),
        components = {},
        props      = {},
        overlays   = {},
        features   = {},
        hair       = { try(getHairColour, ped), try(getHairHigh, ped) },
        eyes       = try(getEyeColour, ped),
    }

    for slot = 0, 11 do
        shot.components[slot] = {
            drawable = GetPedDrawableVariation(ped, slot),
            texture  = GetPedTextureVariation(ped, slot),
            palette  = GetPedPaletteVariation(ped, slot),
        }
    end

    for slot = 0, 7 do
        shot.props[slot] = {
            index   = GetPedPropIndex(ped, slot),
            texture = GetPedPropTextureIndex(ped, slot),
        }
    end

    for overlay = 0, 12 do
        local ok, value, colourType, colour, second, opacity = pcall(GetPedHeadOverlayData, ped, overlay)

        if ok and value then
            shot.overlays[overlay] = { value = value, colourType = colourType, colour = colour, second = second, opacity = opacity }
        end
    end

    for feature = 0, 19 do
        shot.features[feature] = try(getFaceFeature, ped, feature)
    end

    local ok, one, two, three, oneSkin, twoSkin, threeSkin, mix, skinMix, thirdMix = pcall(GetPedHeadBlendData, ped)

    if ok and type(one) == "table" then
        shot.blend = one
    elseif ok and one then
        shot.blend = {
            shapeFirst = one, shapeSecond = two, shapeThird = three,
            skinFirst = oneSkin, skinSecond = twoSkin, skinThird = threeSkin,
            shapeMix = mix, skinMix = skinMix, thirdMix = thirdMix,
        }
    end

    ownPed = shot
end

local function wearModel(hash)
    if not loadModel(hash) then return false end

    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)

    return true
end

local function restorePed()
    if not ownPed then return end

    local shot = ownPed

    ownPed = nil
    state.ped = ""

    if not wearModel(shot.model) then
        say("could not put your own ped back -- the model would not load")
        return
    end

    local ped = PlayerPedId()

    if shot.blend then
        pcall(SetPedHeadBlendData, ped,
            shot.blend.shapeFirst or 0, shot.blend.shapeSecond or 0, shot.blend.shapeThird or 0,
            shot.blend.skinFirst or 0, shot.blend.skinSecond or 0, shot.blend.skinThird or 0,
            shot.blend.shapeMix or 0.0, shot.blend.skinMix or 0.0, shot.blend.thirdMix or 0.0,
            false)
    end

    for feature, value in pairs(shot.features) do
        if value then pcall(SetPedFaceFeature, ped, feature, value + 0.0) end
    end

    for overlay, data in pairs(shot.overlays) do
        pcall(SetPedHeadOverlay, ped, overlay, data.value, (data.opacity or 1.0) + 0.0)

        if data.colourType and setOverlayHue then
            pcall(setOverlayHue, ped, overlay, data.colourType, data.colour or 0, data.second or 0)
        end
    end

    if shot.hair[1] and setHairColour then pcall(setHairColour, ped, shot.hair[1], shot.hair[2] or 0) end
    if shot.eyes and setEyeColour then pcall(setEyeColour, ped, shot.eyes) end

    for slot, data in pairs(shot.components) do
        SetPedComponentVariation(ped, slot, data.drawable, data.texture, data.palette or 0)
    end

    for slot, data in pairs(shot.props) do
        if data.index == -1 then
            ClearPedProp(ped, slot)
        else
            SetPedPropIndex(ped, slot, data.index, data.texture, true)
        end
    end
end

local function swapPed(model)
    model = type(model) == "string" and model:gsub("%s+", "") or ""

    if model == "" then
        restorePed()
        rebuild()

        return true
    end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelAPed(hash) then
        say(("'%s' is not a ped model"):format(model))

        return false, ("'%s' is not a ped model"):format(model)
    end

    snapshotPed()

    if not wearModel(hash) then
        return false, ("'%s' would not load"):format(model)
    end

    state.ped = model

    SetPedDefaultComponentVariation(PlayerPedId())

    rebuild()

    return true
end

local playerAnimating = false

local function ambientAnims(ped, allowed)
    SetPedCanPlayAmbientAnims(ped, allowed)
    SetPedCanPlayAmbientBaseAnims(ped, allowed)
    SetPedCanPlayGestureAnims(ped, allowed)
    SetPedCanPlayVisemeAnims(ped, allowed, false)
end

local function settlePlayer()
    local ped = PlayerPedId()

    if not DoesEntityExist(ped) then return end

    -- Freezing alone will not stop the idle sidestep; the ambient layer has to go.
    ambientAnims(ped, false)

    if playerAnimating then return end

    ClearPedTasksImmediately(ped)
    TaskStandStill(ped, -1)
end

local function releasePlayer()
    local ped = PlayerPedId()

    if not DoesEntityExist(ped) then return end

    ambientAnims(ped, true)
    ClearPedTasks(ped)
end

local function enter()
    if open then return end

    open = true
    hadFocus = IsNuiFocused()

    GG_EDITOR_STAGE.enter()

    cursor = true

    SetNuiFocus(true, true)

    watchCursor()

    playerAnimating = false

    settlePlayer()

    CreateThread(function()
        local mode = GetFollowPedCamViewMode()

        while open do
            local now = GetFollowPedCamViewMode()

            if now ~= mode then
                mode = now

                settlePlayer()
            end

            Wait(250)
        end
    end)

    CreateThread(function()
        while open do
            SendNUIMessage({
                action = "attach_camera",
                data   = {
                    POSITION = GetFinalRenderedCamCoord(),
                    ROTATION = GetFinalRenderedCamRot(2),
                    FOV      = GetFinalRenderedCamFov(),
                },
            })

            Wait(0)
        end
    end)

    SendNUIMessage({ action = "attach_open", data = { OPEN = true } })
end

local function modelTop(name)
    if type(name) ~= "string" or name == "" then return nil end

    local hash = joaat(name)

    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    local _, maximum = GetModelDimensions(hash)

    SetModelAsNoLongerNeeded(hash)

    return maximum and maximum.z or nil
end

local function vec3of(value)
    value = type(value) == "table" and value or {}

    return {
        x = tonumber(value.x) or 0.0,
        y = tonumber(value.y) or 0.0,
        z = tonumber(value.z) or 0.0,
    }
end

local function publishJob()
    if not job then
        SendNUIMessage({ action = "attach_job", data = { ACTIVE = false } })
        return
    end

    SendNUIMessage({
        action = "attach_job",
        data   = {
            ACTIVE  = true,
            TITLE   = job.title,
            SUBJECT = job.subject,
            VEHICLE = job.vehicle,
            KIT     = job.kit,
            KITS    = job.kitList,
        },
    })
end
local function exit()
    if not open then return end

    open = false
    cursor = true

    clearProp()
    clearCar()
    clearAnchor()
    releasePlayer()
    restorePed()
    GG_EDITOR_STAGE.leave()

    frame = nil

    SetNuiFocus(hadFocus, hadFocus)

    SendNUIMessage({ action = "attach_open", data = { OPEN = false } })

    if job then
        local answer, result, failed = job.answer, job.result, job.failed

        job = nil

        publishJob()

        answer:resolve(result or failed)
    end
end
local function applyKit(id)
    if not job then return end

    local chosen

    for _, kit in ipairs(job.kits) do
        if kit.id == id then chosen = kit break end
    end

    if not chosen then return end

    job.kit   = chosen.id
    job.props = chosen.props or {}

    local primary = job.props[1]

    if not primary or type(primary.model) ~= "string" or primary.model == "" then
        clearProp()
        publishProp()
        publishJob()
        return
    end

    spawn(primary.model)
    attachFollowers()

    rebuild()
    publishJob()
end

local function runJob(options, owner)
    if open then return "the placement editor is already open" end
    if type(options) ~= "table" then return "nothing to place" end

    local kits, list = {}, {}

    for index, kit in ipairs(options.kits or {}) do
        if type(kit) ~= "table" then
            fault("kit %d is a %s, not a table", index, type(kit))
        elseif type(kit.id) ~= "string" or kit.id == "" then
            fault("kit %d has no id", index)
        else
            local first = type(kit.props) == "table" and kit.props[1] or nil
            local model = first and first.model
            local available = type(model) == "string" and model ~= "" and IsModelInCdimage(joaat(model))

            kits[#kits + 1] = kit
            list[#list + 1] = {
                id = kit.id,
                label = (kit.label or kit.id) .. (available and "" or "  --  not streamed"),
            }
        end
    end

    if #kits == 0 then
        fault("no usable kits arrived -- opening on the placeholder")

        kits[1] = PLACEHOLDER_KIT
        list[1] = { id = PLACEHOLDER_KIT.id, label = PLACEHOLDER_KIT.label }
    end

    job = {
        owner   = owner,
        title   = options.title or "Placement",
        subject = options.subject,
        vehicle = options.vehicle,
        color   = type(options.color) == "table" and options.color or nil,
        properties = type(options.properties) == "table" and options.properties or nil,
        kits    = kits,
        kitList = list,
        kit     = options.kit,
        answer  = promise.new(),
    }

    local known = false

    for _, kit in ipairs(kits) do
        if kit.id == job.kit then known = true break end
    end

    if not known then job.kit = kits[1].id end

    state.subject  = "prop"
    state.target   = "vehicle"
    state.boneName = (type(options.bone) == "string" and options.bone ~= "") and options.bone or "chassis"
    state.pos      = vec3of(options.pos)
    state.rot      = vec3of(options.rot)

    if state.pos.x == 0.0 and state.pos.y == 0.0 and state.pos.z == 0.0 then
        local here = modelTop(options.vehicle)
        local authored = modelTop(options.authored_for)

        if here and authored then
            state.pos.z = here - authored
        elseif here then
            state.pos.z = here
        end
    end

    enter()

    CreateThread(function()
        if not spawnCar(options.vehicle) then
            fault("%s would not spawn", tostring(options.vehicle))

            if job then
                job.failed = ("%s would not spawn"):format(tostring(options.vehicle))
            end

            exit()
            return
        end

        local seated, seatErr = pcall(ride)

        if not seated then fault("could not seat: %s", tostring(seatErr)) end

        if not job then
            fault("job vanished before the kit went on")
            return
        end

        local fitted, fitErr = pcall(applyKit, job.kit)

        if not fitted then fault("could not fit the kit: %s", tostring(fitErr)) end
    end)

    return Citizen.Await(job.answer)
end

RegisterNUICallback("attach_enter", function(_, cb)
    cb({ ok = true })

    enter()
end)

RegisterNUICallback("attach_look", function(data, cb)
    cb({ ok = true })

    setCursor(not (data and data.free == true))
end)

RegisterNUICallback("attach_exit", function(_, cb)
    cb({ ok = true })

    exit()
end)

RegisterNUICallback("attach_spawn", function(data, cb)
    cb({ ok = true })

    CreateThread(function()
        spawn(data and data.model)
    end)
end)

RegisterNUICallback("attach_clear", function(_, cb)
    cb({ ok = true })

    clearProp()

    state.model = ""
end)

RegisterNUICallback("attach_target", function(data, cb)
    cb({ ok = true })

    local target = data and data.target

    if target ~= "ped" and target ~= "vehicle" and target ~= "prop" then return end

    state.target = target

    CreateThread(function()
        if target == "vehicle" then
            clearAnchor()
            spawnCar(data.vehicle or state.vehicle)
        elseif target == "prop" then
            clearCar()
            spawnAnchor(type(data.anchor) == "string" and data.anchor ~= "" and data.anchor or state.anchor)
        else
            clearCar()
            clearAnchor()
        end

        rebuild()

        SendNUIMessage({
            action = "attach_target",
            data   = { TARGET = target, VEHICLE = state.vehicle, ANCHOR = state.anchor },
        })
    end)
end)

RegisterNUICallback("attach_subject", function(data, cb)
    cb({ ok = true })

    local subject = data and data.subject

    if subject ~= "prop" and subject ~= "ped" then return end

    state.subject = subject

    CreateThread(function()
        local keepPos, keepRot = state.pos, state.rot
        local model = type(data.model) == "string" and data.model or ""

        if model ~= "" then
            spawn(model)
        else
            clearProp()

            state.model = ""
        end

        state.pos, state.rot = keepPos, keepRot

        rebuild()

        SendNUIMessage({ action = "attach_values", data = { POS = state.pos, ROT = state.rot } })
    end)
end)

RegisterNUICallback("attach_alive", function(data, cb)
    cb({ ok = true })

    state.alive = (data and data.alive) ~= false

    if state.subject ~= "ped" or state.model == "" then return end

    CreateThread(function()
        local keepPos, keepRot = state.pos, state.rot

        spawn(state.model)

        state.pos, state.rot = keepPos, keepRot

        rebuild()
    end)
end)

RegisterNUICallback("attach_subject_anim", function(data, cb)
    cb({ ok = true })

    state.anim = {
        dict = type(data) == "table" and type(data.dict) == "string" and data.dict or "",
        name = type(data) == "table" and type(data.name) == "string" and data.name or "",
    }

    if state.subject ~= "ped" or not (prop and DoesEntityExist(prop)) then return end

    CreateThread(function()
        if not state.alive then return end

        ClearPedTasksImmediately(prop)

        playOn(prop, state.anim.dict, state.anim.name)
    end)
end)

RegisterNUICallback("attach_flags", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.flags) ~= "table" then return end

    for name in pairs(state.flags) do
        if data.flags[name] ~= nil then state.flags[name] = data.flags[name] == true end
    end

    if state.subject ~= "ped" then return end

    applyFlags(prop)
end)

RegisterNUICallback("attach_anchor", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.anchor) ~= "string" then return end

    CreateThread(function()
        if spawnAnchor(data.anchor) then
            rebuild()

            SendNUIMessage({ action = "attach_target", data = { TARGET = state.target, VEHICLE = state.vehicle, ANCHOR = state.anchor } })
        end
    end)
end)

RegisterNUICallback("attach_ped", function(data, cb)
    cb({ ok = true })

    CreateThread(function()
        local ok, problem = swapPed(data and data.ped)

        SendNUIMessage({
            action = "attach_ped",
            data   = { PED = state.ped, ERROR = (not ok) and problem or false },
        })
    end)
end)

RegisterNUICallback("attach_vehicle", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.vehicle) ~= "string" then return end

    CreateThread(function()
        if spawnCar(data.vehicle) then
            rebuild()

            SendNUIMessage({ action = "attach_target", data = { TARGET = state.target, VEHICLE = state.vehicle } })
        end
    end)
end)

RegisterNUICallback("attach_bone", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    if type(data.boneName) == "string" and data.boneName ~= "" then
        state.boneName = data.boneName
    end

    local bone = tonumber(data.bone)

    if bone then state.bone = math.floor(bone) end

    CreateThread(rebuild)
end)

RegisterNUICallback("attach_gizmo", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or not data.at then return end

    local right, forward, up = data.right, data.forward, data.up

    local at = {
        x = data.at.x - ((right.x * prop_centre.x) + (forward.x * prop_centre.y) + (up.x * prop_centre.z)),
        y = data.at.y - ((right.y * prop_centre.x) + (forward.y * prop_centre.y) + (up.y * prop_centre.z)),
        z = data.at.z - ((right.z * prop_centre.x) + (forward.z * prop_centre.y) + (up.z * prop_centre.z)),
    }

    local pos, rot = toBoneSpace(at, right, forward, up)

    if not pos then return end

    state.pos, state.rot = pos, rot

    reattach()

    SendNUIMessage({ action = "attach_values", data = { POS = pos, ROT = rot } })
end)

RegisterNUICallback("attach_example", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    local bone = tonumber(data.bone)

    if bone then state.bone = math.floor(bone) end

    if type(data.pos) == "table" then
        state.pos = {
            x = tonumber(data.pos.x) or 0.0,
            y = tonumber(data.pos.y) or 0.0,
            z = tonumber(data.pos.z) or 0.0,
        }
    end

    if type(data.rot) == "table" then
        state.rot = {
            x = tonumber(data.rot.x) or 0.0,
            y = tonumber(data.rot.y) or 0.0,
            z = tonumber(data.rot.z) or 0.0,
        }
    end

    CreateThread(function()
        local keepPos, keepRot = state.pos, state.rot

        if type(data.model) == "string" and data.model ~= "" then
            spawn(data.model)
        end

        state.pos, state.rot = keepPos, keepRot

        rebuild()

        SendNUIMessage({ action = "attach_values", data = { POS = state.pos, ROT = state.rot } })
    end)
end)

RegisterNUICallback("attach_bench", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    CreateThread(function()
        swapPed(type(data.ped) == "string" and data.ped or "")

        state.subject = data.subject == "ped" and "ped" or "prop"
        state.alive   = data.alive ~= false

        if type(data.flags) == "table" then
            for name in pairs(state.flags) do
                if data.flags[name] ~= nil then state.flags[name] = data.flags[name] == true end
            end
        end

        state.anim = {
            dict = type(data.subjectAnimDict) == "string" and data.subjectAnimDict or "",
            name = type(data.subjectAnimName) == "string" and data.subjectAnimName or "",
        }

        state.target = (data.target == "vehicle" or data.target == "prop") and data.target or "ped"

        if state.target == "vehicle" then
            clearAnchor()
            spawnCar(type(data.vehicle) == "string" and data.vehicle or state.vehicle)
        elseif state.target == "prop" then
            clearCar()
            spawnAnchor(type(data.anchor) == "string" and data.anchor or state.anchor)
        else
            clearCar()
            clearAnchor()
        end

        local bone = tonumber(data.bone)

        if bone then state.bone = math.floor(bone) end
        if type(data.boneName) == "string" and data.boneName ~= "" then state.boneName = data.boneName end

        if type(data.model) == "string" and data.model ~= "" then
            spawn(data.model)
        else
            clearProp()

            state.model = ""
        end

        if type(data.pos) == "table" then
            state.pos = { x = tonumber(data.pos.x) or 0.0, y = tonumber(data.pos.y) or 0.0, z = tonumber(data.pos.z) or 0.0 }
        end

        if type(data.rot) == "table" then
            state.rot = { x = tonumber(data.rot.x) or 0.0, y = tonumber(data.rot.y) or 0.0, z = tonumber(data.rot.z) or 0.0 }
        end

        rebuild()

        SendNUIMessage({ action = "attach_target", data = { TARGET = state.target, VEHICLE = state.vehicle, ANCHOR = state.anchor } })
        SendNUIMessage({ action = "attach_ped", data = { PED = state.ped, ERROR = false } })
        SendNUIMessage({ action = "attach_values", data = { POS = state.pos, ROT = state.rot } })
    end)
end)

RegisterNUICallback("attach_reset", function(_, cb)
    cb({ ok = true })

    state.pos = { x = 0.0, y = 0.0, z = 0.0 }
    state.rot = { x = 0.0, y = 0.0, z = 0.0 }

    CreateThread(rebuild)

    SendNUIMessage({ action = "attach_values", data = { POS = state.pos, ROT = state.rot } })
end)
RegisterNUICallback("attach_anim", function(data, cb)
    cb({ ok = true })

    local dict = data and data.dict
    local anim = data and data.anim
    local ped  = PlayerPedId()

    if type(dict) ~= "string" or dict == "" or type(anim) ~= "string" or anim == "" then
        playerAnimating = false

        ClearPedTasks(ped)
        settlePlayer()

        return
    end

    playerAnimating = true

    CreateThread(function()
        RequestAnimDict(dict)

        local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

        while not HasAnimDictLoaded(dict) do
            if GetGameTimer() > deadline then
                say(("animation dictionary '%s' would not load"):format(dict))
                return
            end

            Wait(0)
        end

        TaskPlayAnim(ped, dict, anim, 5.0, 5.0, -1, 15, 0, false, false, false)
        RemoveAnimDict(dict)
    end)
end)

RegisterNUICallback("attach_kit", function(data, cb)
    cb({ ok = true })

    if not job or type(data) ~= "table" or type(data.kit) ~= "string" then return end

    CreateThread(function()
        applyKit(data.kit)
    end)
end)

RegisterNUICallback("attach_save", function(_, cb)
    cb({ ok = true })

    if not job then return end

    job.result = {
        kit = job.kit,
        pos = { x = state.pos.x, y = state.pos.y, z = state.pos.z },
        rot = { x = state.rot.x, y = state.rot.y, z = state.rot.z },
    }

    exit()
end)

RegisterNUICallback("attach_job", function(_, cb)
    cb({ ok = true })

    publishJob()
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource ~= RESOURCE then
        if job and job.owner == resource then exit() end
        return
    end

    clearProp()
    clearCar()
    clearAnchor()
    releasePlayer()

    restorePed()

    if open then
        GG_EDITOR_STAGE.leave()

        SetNuiFocus(false, false)

        open = false
    end

    if job then
        local answer = job.answer

        job = nil

        answer:resolve(nil)
    end
end)

AddEventHandler("gg_lib:attach:place", function(resource, id, options)
    if type(resource) ~= "string" or id == nil then return end

    TriggerEvent("gg_lib:attach:placeAccepted", resource, id)

    CreateThread(function()
        local answer

        if open then
            answer = "the placement editor is already open"
        else
            local ok, result = pcall(runJob, options, resource)

            if ok then
                answer = result
            else
                say(("placement failed: %s"):format(tostring(result)))
                answer = "the placement editor errored -- see the client console"
            end
        end

        TriggerEvent("gg_lib:attach:placeResult", resource, id, answer)
    end)
end)
exports("ggAttachEditor", function()
    enter()

    return true
end)

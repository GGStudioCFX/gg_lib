
GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }
GG_EDITOR_BUCKET.enter = GG_EDITOR_BUCKET.enter or function() return false end
GG_EDITOR_BUCKET.leave = GG_EDITOR_BUCKET.leave or function() end

local RESOURCE = GetCurrentResourceName()

local LOAD_TIMEOUT_MS = 8000

local CAST = {
    "a_m_y_genstreet_02",
    "a_f_y_hipster_02",
    "a_m_m_business_01",
    "a_f_m_bevhills_02",
    "a_m_y_skater_01",
    "a_f_y_business_02",
    "a_m_y_hipster_01",
    "a_f_y_tourist_01",
    "a_m_m_skater_01",
}

local STAGE_MODEL  = "stt_prop_stunt_bblock_huge_01"
local STAGE_TOP    = 0.199
local STAGE_HEIGHT = 300.0

local SKY_RADIUS = 50.0
local SKY_LIFT   = 4.0

local SKY_R, SKY_G, SKY_B = 30, 32, 38

local CAM_SLOW   = 0.05
local CAM_NORMAL = 0.16
local CAM_FAST   = 0.45
local LOOK_SPEED = 5.0

local PEN_RADIUS  = 22.0
local CAM_BACK    = 9.0
local CAM_EYE     = 2.2
local CAM_FLOOR   = 0.6
local CAM_CEILING = 18.0

local PARK_BACK = 13.0

local SCENE_DISTANCE = 10.0

local STANDIN_CAR  = "asea"
local STANDIN_BIKE = "bagger"

local SEAT_LIFT = 0.5

local scene = { id = nil, cast = {}, bodies = {}, x = 0.0, y = 0.0, z = 0.0, heading = 0.0 }
local stage = { piece = nil, floor = nil, home = nil, cam = nil, pos = nil, rot = nil, active = false }

local function say(message)
    print(("[gg_lib] %s"):format(message))
end

local function loadModel(model)
    local hash = joaat(model)

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    return hash
end

local function loadDict(dict)
    if type(dict) ~= "string" or dict == "" then return false end
    if not DoesAnimDictExist(dict) then return false end

    RequestAnimDict(dict)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

local function stopCamera()
    if not stage.active then return end

    stage.active = false

    RenderScriptCams(false, true, 400, true, true)

    if stage.cam then
        DestroyCam(stage.cam, true)

        stage.cam = nil
    end

    ClearFocus()
end

local function moveCamera(centre)
    if GG_VIEWER.looking() then
        local speed = CAM_NORMAL

        if IsDisabledControlPressed(0, 21) then speed = CAM_FAST end   -- shift
        if IsDisabledControlPressed(0, 36) then speed = CAM_SLOW end   -- ctrl

        local lookX = GetDisabledControlNormal(0, 1) * LOOK_SPEED
        local lookY = GetDisabledControlNormal(0, 2) * LOOK_SPEED

        stage.rot.pitch = math.max(-89.0, math.min(89.0, stage.rot.pitch - lookY))
        stage.rot.yaw   = (stage.rot.yaw - lookX) % 360

        local yaw   = math.rad(stage.rot.yaw)
        local pitch = math.rad(stage.rot.pitch)

        local fx, fy, fz = -math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)
        local rx, ry = math.cos(yaw), math.sin(yaw)

        local mx, my, mz = 0.0, 0.0, 0.0

        if IsDisabledControlPressed(0, 32) then mx, my, mz = mx + fx, my + fy, mz + fz end   -- W
        if IsDisabledControlPressed(0, 33) then mx, my, mz = mx - fx, my - fy, mz - fz end   -- S
        if IsDisabledControlPressed(0, 34) then mx, my = mx - rx, my - ry end                -- A
        if IsDisabledControlPressed(0, 35) then mx, my = mx + rx, my + ry end                -- D
        if IsDisabledControlPressed(0, 22) then mz = mz + 1.0 end                            -- space
        if IsDisabledControlPressed(0, 44) then mz = mz - 1.0 end                            -- Q

        stage.pos.x = stage.pos.x + (mx * speed)
        stage.pos.y = stage.pos.y + (my * speed)
        stage.pos.z = stage.pos.z + (mz * speed)

        local dx, dy = stage.pos.x - centre.x, stage.pos.y - centre.y
        local away   = math.sqrt((dx * dx) + (dy * dy))

        if away > PEN_RADIUS then
            stage.pos.x = centre.x + (dx * (PEN_RADIUS / away))
            stage.pos.y = centre.y + (dy * (PEN_RADIUS / away))
        end

        stage.pos.z = math.max(centre.z + CAM_FLOOR, math.min(centre.z + CAM_CEILING, stage.pos.z))
    end

    SetCamCoord(stage.cam, stage.pos.x, stage.pos.y, stage.pos.z)
    SetCamRot(stage.cam, stage.rot.pitch, 0.0, stage.rot.yaw, 2)

    SetFocusPosAndVel(stage.pos.x, stage.pos.y, stage.pos.z, 0.0, 0.0, 0.0)
end

local function drawStage(centre)
    DrawMarker(
        28,
        centre.x, centre.y, centre.z + SKY_LIFT,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        SKY_RADIUS, SKY_RADIUS, SKY_RADIUS,
        SKY_R, SKY_G, SKY_B, 255,
        false, true, 2, false, nil, nil, false
    )
end

local function startCamera(centre)
    stage.pos = { x = centre.x, y = centre.y - CAM_BACK, z = centre.z + CAM_EYE }
    stage.rot = { pitch = -8.0, yaw = 0.0 }

    stage.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetCamCoord(stage.cam, stage.pos.x, stage.pos.y, stage.pos.z)
    SetCamRot(stage.cam, stage.rot.pitch, 0.0, stage.rot.yaw, 2)
    SetCamFov(stage.cam, 55.0)
    SetCamActive(stage.cam, true)

    RenderScriptCams(true, true, 500, true, true)

    stage.active = true

    CreateThread(function()
        while stage.active do
            moveCamera(centre)
            drawStage(centre)

            Wait(0)
        end
    end)
end

local function clearStage(quick)
    stopCamera()

    if stage.piece and DoesEntityExist(stage.piece) then DeleteEntity(stage.piece) end

    stage.piece = nil
    stage.floor = nil

    if stage.home then
        local ped  = PlayerPedId()
        local home = stage.home

        stage.home = nil

        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, false)

        if quick then
            SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, false)
            FreezeEntityPosition(ped, false)
        else
            FreezeEntityPosition(ped, true)
            SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, false)

            RequestCollisionAtCoord(home.x, home.y, home.z)

            local deadline = GetGameTimer() + 3000

            while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
                Wait(0)
            end

            FreezeEntityPosition(ped, false)
        end
    end

    GG_EDITOR_BUCKET.leave()
end

local function buildStage()
    if stage.floor then return stage.floor end

    local hash = loadModel(STAGE_MODEL)

    if not hash then return nil end

    GG_EDITOR_BUCKET.enter()

    local ped = PlayerPedId()
    local at  = GetEntityCoords(ped)

    stage.home = { x = at.x, y = at.y, z = at.z }

    local baseZ = at.z + STAGE_HEIGHT

    stage.piece = CreateObject(hash, at.x, at.y, baseZ, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not stage.piece or not DoesEntityExist(stage.piece) then
        stage.piece = nil
        stage.home  = nil

        GG_EDITOR_BUCKET.leave()

        return nil
    end

    FreezeEntityPosition(stage.piece, true)
    SetEntityCollision(stage.piece, true, true)
    SetEntityVisible(stage.piece, false, false)

    local floor = { x = at.x, y = at.y, z = baseZ + STAGE_TOP }

    stage.floor = floor

    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCoords(ped, floor.x, floor.y - PARK_BACK, floor.z + 0.2, false, false, false, false)

    startCamera(floor)

    Wait(300)

    return floor
end

local function clear()
    if scene.id then
        DisposeSynchronizedScene(scene.id)

        scene.id = nil
    end

    for index = 1, #scene.cast do
        local entity = scene.cast[index]

        if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    end

    scene.cast   = {}
    scene.bodies = {}
end

local function inFront()
    local ped = PlayerPedId()
    local at  = GetEntityCoords(ped)
    local rot = GetGameplayCamRot(2)

    local yaw = math.rad(rot.z)

    local x = at.x - (math.sin(yaw) * SCENE_DISTANCE)
    local y = at.y + (math.cos(yaw) * SCENE_DISTANCE)

    local found, groundZ = GetGroundZFor_3dCoord(x, y, at.z + 3.0, false)

    return { x = x, y = y, z = found and groundZ or at.z }, (rot.z + 180.0) % 360
end

local function needsStandin(data)
    if data.category ~= "Vehicle" then return false end

    for index = 1, #(data.objects or {}) do
        local model = data.objects[index].m

        if type(model) == "string" and model ~= "" then
            local hash = joaat(model)

            if IsModelInCdimage(hash) and IsModelAVehicle(hash) then return false end
        end
    end

    return true
end

local function addStandin(data, surfaceZ)
    local name = type(data.name) == "string" and data.name:lower() or ""
    local bike = name:find("motorcycle", 1, true) or name:find("bike", 1, true)

    local hash = loadModel(bike and STANDIN_BIKE or STANDIN_CAR)

    if not hash then return end

    local car = CreateVehicle(hash, scene.x, scene.y, surfaceZ, scene.heading, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not car or not DoesEntityExist(car) then return end

    scene.cast[#scene.cast + 1] = car

    SetEntityCollision(car, false, false)
    FreezeEntityPosition(car, true)
    SetVehicleDoorsLocked(car, 2)
end

local function settle(anchor, seated)
    if not scene.id then return end

    Wait(250)

    local minX, maxX, minY, maxY, lowest

    for index = 1, #scene.cast do
        local entity = scene.cast[index]

        if DoesEntityExist(entity) then
            local at = GetEntityCoords(entity)

            if not minX or at.x < minX then minX = at.x end
            if not maxX or at.x > maxX then maxX = at.x end
            if not minY or at.y < minY then minY = at.y end
            if not maxY or at.y > maxY then maxY = at.y end
        end
    end

    for index = 1, #scene.bodies do
        local body = scene.bodies[index]

        if DoesEntityExist(body) then
            local z = GetEntityCoords(body).z

            if not lowest or z < lowest then lowest = z end
        end
    end

    if minX then
        local shiftX = anchor.x - ((minX + maxX) * 0.5)
        local shiftY = anchor.y - ((minY + maxY) * 0.5)
        local shiftZ = lowest and ((anchor.z + (seated and SEAT_LIFT or 0.0)) - lowest) or 0.0

        if math.abs(shiftX) > 0.05 or math.abs(shiftY) > 0.05 or math.abs(shiftZ) > 0.05 then
            scene.x = scene.x + shiftX
            scene.y = scene.y + shiftY
            scene.z = scene.z + shiftZ

            SetSynchronizedSceneOrigin(scene.id, scene.x, scene.y, scene.z, 0.0, 0.0, scene.heading, 2)
        end
    end

    for index = 1, #scene.cast do
        local entity = scene.cast[index]

        if DoesEntityExist(entity) then SetEntityVisible(entity, true, false) end
    end
end

RegisterNUICallback("scene_open", function(data, cb)
    cb({ ok = true })

    GG_VIEWER.open("scenes")

    if type(data) ~= "table" or not data.stage then return end

    CreateThread(function()
        if not buildStage() then
            SendNUIMessage({ action = "scene_state", data = { STAGE = false, ERROR = STAGE_MODEL } })

            return
        end

        SendNUIMessage({ action = "scene_state", data = { STAGE = true } })
    end)
end)

RegisterNUICallback("scene_play", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.actors) ~= "table" or #data.actors == 0 then return end

    CreateThread(function()
        clear()

        for index = 1, #data.actors do
            if not loadDict(data.actors[index].d) then
                say(("scene animation '%s' would not load"):format(tostring(data.actors[index].d)))

                SendNUIMessage({ action = "scene_state", data = { PLAYING = false, ERROR = data.actors[index].d } })

                return
            end
        end

        local anchor, heading

        if data.stage then
            anchor = buildStage()

            if not anchor then
                SendNUIMessage({ action = "scene_state", data = { PLAYING = false, ERROR = STAGE_MODEL } })

                return
            end

            heading = 180.0
        else
            clearStage()

            anchor, heading = inFront()
        end

        scene.x = anchor.x
        scene.y = anchor.y
        scene.z = anchor.z + (tonumber(data.deltaZ) or 0.0)

        scene.heading = heading

        scene.id = CreateSynchronizedScene(scene.x, scene.y, scene.z, 0.0, 0.0, heading, 2)

        SetSynchronizedSceneLooped(scene.id, data.loop == true)

        local isDog = type(data.name) == "string" and data.name:lower():find("dog", 1, true) ~= nil

        for index = 1, #data.actors do
            local actor = data.actors[index]
            local model = isDog and index > 1 and "a_c_rottweiler" or CAST[((index - 1) % #CAST) + 1]
            local hash  = loadModel(model)

            if hash then
                local body = CreatePed(4, hash, scene.x, scene.y, scene.z, heading, false, false)

                SetModelAsNoLongerNeeded(hash)

                if DoesEntityExist(body) then
                    scene.cast[#scene.cast + 1]     = body
                    scene.bodies[#scene.bodies + 1] = body

                    SetEntityInvincible(body, true)
                    SetBlockingOfNonTemporaryEvents(body, true)
                    SetPedCanRagdoll(body, false)

                    SetEntityVisible(body, false, false)

                    TaskSynchronizedScene(body, scene.id, actor.d, actor.a, 1.5, -4.0, 16, 1148846080, 1000.0, 0)
                end
            end
        end

        for index = 1, #(data.objects or {}) do
            local prop = data.objects[index]
            local hash = loadModel(prop.m)

            if hash and loadDict(prop.d) then
                local entity

                if IsModelAVehicle(hash) then
                    entity = CreateVehicle(hash, scene.x, scene.y, scene.z, heading, false, false)
                else
                    entity = CreateObject(hash, scene.x, scene.y, scene.z, false, false, false)
                end

                SetModelAsNoLongerNeeded(hash)

                if entity and DoesEntityExist(entity) then
                    scene.cast[#scene.cast + 1] = entity

                    SetEntityVisible(entity, false, false)

                    PlaySynchronizedEntityAnim(entity, scene.id, prop.a, prop.d, 1000.0, 1000.0, 16, 1000.0)
                end
            end
        end

        local seated = needsStandin(data)

        settle(anchor, seated)

        if seated then addStandin(data, anchor.z) end

        local seconds = GetAnimDuration(data.actors[1].d, data.actors[1].a) or 0.0

        SendNUIMessage({
            action = "scene_state",
            data   = { PLAYING = true, CAST = #scene.cast, SECONDS = seconds, STAGE = data.stage == true },
        })
    end)
end)

RegisterNUICallback("scene_close", function(_, cb)
    cb({ ok = true })

    GG_VIEWER.close()

    clear()

    CreateThread(clearStage)
end)

RegisterNUICallback("scene_stop", function(_, cb)
    cb({ ok = true })

    clear()

    SendNUIMessage({ action = "scene_state", data = { PLAYING = false } })
end)

RegisterNUICallback("scene_ground", function(_, cb)
    cb({ ok = true })

    clear()

    CreateThread(clearStage)

    SendNUIMessage({ action = "scene_state", data = { PLAYING = false, STAGE = false } })
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end

    clear()
    clearStage(true)
end)

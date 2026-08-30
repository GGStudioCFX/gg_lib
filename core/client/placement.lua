
gg = gg or {}
gg.print = gg.print or { error = print, warn = print }

GG_PAUSE_GUARD = GG_PAUSE_GUARD or { holders = 0 }
GG_PAUSE_GUARD.acquire = GG_PAUSE_GUARD.acquire or function() end
GG_PAUSE_GUARD.release = GG_PAUSE_GUARD.release or function() end

GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }
GG_EDITOR_BUCKET.enter = GG_EDITOR_BUCKET.enter or function() return false end
GG_EDITOR_BUCKET.leave = GG_EDITOR_BUCKET.leave or function() end

do
    local source = LoadResourceFile("gg_lib", "modules/tool/client.lua")
    local chunk  = source and load(source, "@@gg_lib/modules/tool/client.lua", "t")

    if chunk then
        local ok, err = pcall(chunk)
        if not ok then
            print(("^1[gg_lib] tool module failed to load: %s^0"):format(err))
        end
    else
        print("^1[gg_lib] could not read modules/tool/client.lua -- restart gg_lib^0")
    end
end

local PED_CENTRE_OFFSET = 1.03

local RAY_DISTANCE  = 60.0
local COARSE_TURN   = 5.0
local FINE_TURN     = 1.0

local preview_ped = nil

local active_state = nil

local function destroyPreview()
    if preview_ped and DoesEntityExist(preview_ped) then
        DeleteEntity(preview_ped)
    end

    preview_ped = nil
end

local function finite(number, fallback)
    number = tonumber(number)

    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end

    return number
end

local function safeCoords(coords, fallback)
    if type(coords) ~= "table" and type(coords) ~= "vector3" and type(coords) ~= "vector4" then
        return fallback
    end

    local x = finite(coords.x, nil)
    local y = finite(coords.y, nil)
    local z = finite(coords.z, nil)

    if not x or not y or not z then return fallback end

    if math.abs(x) > 16000 or math.abs(y) > 16000 or math.abs(z) > 2000 then
        return fallback
    end

    return vector3(x, y, z)
end

local LAST_RESORT_PED = "a_m_m_business_01"

local function fallbackPed()
    return LAST_RESORT_PED
end

local function spawnPreview(model, scene, coords, heading)
    if type(model) ~= "string" or model == "" then model = fallbackPed() end

    local hash = joaat(model)

    if not IsModelValid(hash) then
        hash = joaat(fallbackPed())
        if not IsModelValid(hash) then hash = joaat(LAST_RESORT_PED) end
        if not IsModelValid(hash) then return nil end
    end

    RequestModel(hash)

    for _ = 1, 100 do
        if HasModelLoaded(hash) then break end
        Wait(10)
    end

    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    SetEntityInvincible(ped, true)
    SetEntityCollision(ped, false, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    return ped
end

local SETTLE_MS = 350

local function movePreview(state)
    if not preview_ped or not DoesEntityExist(preview_ped) then return end

    local target = safeCoords(state.coords, nil)
    if not target then return end

    local heading = finite(state.heading, 0.0) % 360
    local moved = not state.last_applied
        or #(target - state.last_applied) > 0.001
        or math.abs(heading - (state.last_heading or -1)) > 0.01

    if moved then
        SetEntityCoordsNoOffset(preview_ped, target.x, target.y, target.z, false, false, false)
        SetEntityHeading(preview_ped, heading)

        state.last_applied = target
        state.last_heading = heading
        state.settled_at   = GetGameTimer() + SETTLE_MS

        if state.scenario_running then
            ClearPedTasksImmediately(preview_ped)
            state.scenario_running = false
        end

        return
    end

    if state.scene and not state.scenario_running and GetGameTimer() >= (state.settled_at or 0) then
        TaskStartScenarioInPlace(preview_ped, state.scene, 0, true)
        state.scenario_running = true
    end
end

local pending_ray = nil
local last_ground = nil

local function groundUnderCursor()
    if pending_ray then
        local status, hit, endCoords = GetShapeTestResult(pending_ray)

        if status ~= 1 then
            pending_ray = nil

            if hit == true or hit == 1 then
                last_ground = safeCoords(endCoords, last_ground)
            end
        end
    end

    if not pending_ray then
        local camCoords = safeCoords(GetGameplayCamCoord(), nil)
        local rotation  = GetGameplayCamRot(2)

        if not camCoords then return last_ground end

        local pitch = math.rad(finite(rotation.x, 0.0))
        local yaw   = math.rad(finite(rotation.z, 0.0))
        local cos   = math.abs(math.cos(pitch))

        local direction = vector3(-math.sin(yaw) * cos, math.cos(yaw) * cos, math.sin(pitch))
        local target    = safeCoords(camCoords + direction * RAY_DISTANCE, nil)

        if not target then return last_ground end

        pending_ray = StartShapeTestRay(
            camCoords.x, camCoords.y, camCoords.z,
            target.x, target.y, target.z,
            -1, preview_ped or PlayerPedId(), 4
        )

        if not last_ground then
            local found, z = GetGroundZFor_3dCoord(target.x, target.y, target.z, false)
            last_ground = safeCoords(vector3(target.x, target.y, found and z or target.z), camCoords)
        end
    end

    return last_ground
end

local gizmo_mode = "translate"

local function pushGizmo(state)
    local camCoords = safeCoords(GetFinalRenderedCamCoord(), nil)
    if not camCoords then return end

    local camRot = GetFinalRenderedCamRot(2)

    SendNUIMessage({
        action = "gg_gizmo",
        data = {
            ACTIVE   = true,
            MODE     = gizmo_mode,
            POSITION = { x = state.coords.x, y = state.coords.y, z = state.coords.z },
            HEADING  = finite(state.heading, 0.0),
            CAMERA   = {
                position = { x = camCoords.x, y = camCoords.y, z = camCoords.z },
                rotation = { x = finite(camRot.x, 0.0), y = finite(camRot.y, 0.0), z = finite(camRot.z, 0.0) },
                fov      = finite(GetFinalRenderedCamFov(), 50.0),
            },
        },
    })
end

local function applyGizmoMove(state, payload)
    if type(payload) ~= "table" then return end

    local moved = safeCoords(payload.position, nil)
    if moved then
        state.coords = moved

        state.drag = false
    end

    local heading = finite(payload.heading, nil)
    if heading then state.heading = heading % 360 end
end

local function pickPosition(initial, preview)
    local ped  = PlayerPedId()
    local here = safeCoords(GetEntityCoords(ped), vector3(0.0, 0.0, 72.0))

    local heading = finite(initial and initial.heading, GetEntityHeading(ped)) % 360
    local start   = safeCoords(initial, here)

    pending_ray = nil
    last_ground = nil

    preview_ped = spawnPreview(preview and preview.model, preview and preview.scene, start, heading)

    local state = {
        coords  = start,
        heading = heading,
        drag    = true,
        fine    = false,
        mode    = "simple",
        cursor  = false,
        scene   = type(preview) == "table" and type(preview.scene) == "string" and preview.scene or nil,
    }

    active_state = state

    local place = { key = "ENTER", control = 191, label = "Place", finish = function(inner)
        return { x = inner.coords.x, y = inner.coords.y, z = inner.coords.z, heading = inner.heading }
    end }

    local cancel = { key = "ESC", control = 200, label = "Cancel", cancel = true }

    local turnUp = { control = 15, action = function(inner)
        inner.heading = (inner.heading + (inner.fine and FINE_TURN or COARSE_TURN)) % 360
    end }

    local turnDown = { key = "Scroll", control = 14, label = "Turn", action = function(inner)
        inner.heading = (inner.heading - (inner.fine and FINE_TURN or COARSE_TURN)) % 360
    end }

    local simple, advanced

    local function setCursor(inner, on)
        inner.cursor = on

        SetNuiFocus(on, on)
        SetNuiFocusKeepInput(on)

        if not on then
            SendNUIMessage({ action = "gg_gizmo", data = { ACTIVE = false } })
        end
    end

    local toggleCursor = { key = "L-ALT", control = 19, label = "Cursor", action = function(inner)
        setCursor(inner, not inner.cursor)
    end }

    local toAdvanced = { key = "E", control = 38, label = "Advanced", action = function(inner)
        inner.mode = "advanced"

        inner.drag = false

        gg.tool.setKeys(advanced)

        setCursor(inner, true)
    end }

    local toSimple = { key = "E", control = 38, label = "Simple", action = function(inner)
        inner.mode = "simple"

        inner.drag = true
        setCursor(inner, false)

        gg.tool.setKeys(simple)
    end }

    simple = { place, cancel, turnUp, turnDown, toAdvanced }

    advanced = {
        place, cancel,
        { key = "R", control = 45, label = "Move / Turn", action = function(inner)
            gizmo_mode = gizmo_mode == "translate" and "rotate" or "translate"

            if inner.cursor then pushGizmo(inner) end
        end },
        toggleCursor,
        toSimple,
    }

    return gg.tool.run({
        title = "Place Ped",
        state = state,
        keys  = simple,
        tick  = function(inner)
            inner.fine = IsDisabledControlPressed(0, 21)

            if inner.drag then
                local ground = groundUnderCursor()

                if ground then
                    inner.coords = vector3(ground.x, ground.y, ground.z + PED_CENTRE_OFFSET)
                end
            end

            local safe = safeCoords(inner.coords, nil)
            if not safe then
                inner.coords = safeCoords(GetEntityCoords(PlayerPedId()), vector3(0.0, 0.0, 72.0))
                return
            end

            inner.coords = safe

            movePreview(inner)

            gg.tool.setInfo({
                { label = "X", value = ("%.2f"):format(safe.x) },
                { label = "Y", value = ("%.2f"):format(safe.y) },
                { label = "Z", value = ("%.2f"):format(safe.z) },
                { label = "Heading", value = ("%.1f"):format(finite(inner.heading, 0.0)) },
            }, inner.mode)

            if inner.cursor then pushGizmo(inner) end
        end,
        cleanup = function(inner)
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            SendNUIMessage({ action = "gg_gizmo", data = { ACTIVE = false } })

            destroyPreview()
        end,
    })
end

RegisterNUICallback("gg_gizmo_move", function(data, cb)
    if active_state then
        pcall(applyGizmoMove, active_state, data)
    end

    cb({})
end)

RegisterNUICallback("settings_pick_coords", function(data, cb)
    if not gg.tool or not gg.tool.run then
        print("^1[gg_lib] placement unavailable: the tool module did not load^0")
        cb({ ok = false })
        return
    end

    if gg.tool.isActive() then
        cb({ ok = false })
        return
    end

    GG_PAUSE_GUARD.acquire()
    GG_EDITOR_BUCKET.enter()

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "settings_placing", data = { PLACING = true } })

    local ok, picked = pcall(pickPosition, data and data.current, data and data.preview)

    active_state = nil

    gg.tool.abort()
    destroyPreview()
    GG_EDITOR_BUCKET.leave()

    SetNuiFocusKeepInput(false)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "settings_placing", data = { PLACING = false } })

    GG_PAUSE_GUARD.release()

    if not ok then
        print(("^1[gg_lib] placement failed: %s^0"):format(picked))
        cb({ ok = false })
        return
    end

    cb({ ok = picked ~= nil, COORDS = picked })
end)

RegisterNUICallback("settings_teleport", function(data, cb)
    local target = safeCoords(data and data.coords, nil)

    if not target then
        cb({ ok = false })
        return
    end

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped

    local heading = finite(data.coords.heading, nil) or finite(data.coords.w, nil)

    SetEntityCoords(entity, target.x, target.y, target.z, false, false, false, false)
    if heading then SetEntityHeading(entity, heading % 360) end

    cb({ ok = true })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= "gg_lib" then return end

    gg.tool.abort()
    destroyPreview()
end)


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

local groundUnderCursor

-- MARK: Freecam

-- A coords column whose preview_object has `freecam = true` picks from a flying camera instead of
-- the player's eyes, so a prop goes down anywhere in sight: across the room, up on a stage, over
-- the road. The prop follows the middle of the screen as it does on foot. WASD flies, the mouse
-- looks, Space and Q go up and down, Shift is fast and Ctrl slow. The camera World List uses.
local CAM_SLOW, CAM_NORMAL, CAM_FAST = 0.08, 0.35, 1.1
local LOOK_SPEED    = 6.0
local FREECAM_REACH = 120.0
local FREECAM_LEASH = 400.0
local FLY_CONTROLS  = { 1, 2, 21, 22, 30, 31, 32, 33, 34, 35, 36, 44 }

local freecam = nil

local function lookAt(from, target)
    local delta = target - from
    local flat  = math.sqrt(delta.x * delta.x + delta.y * delta.y)

    return vector3(math.deg(math.atan(delta.z, math.max(flat, 0.001))), 0.0, math.deg(math.atan(-delta.x, delta.y)) % 360)
end

local function startFreecam(target)
    local ped  = PlayerPedId()
    local feet = safeCoords(GetEntityCoords(ped), vector3(0.0, 0.0, 72.0))

    local pos = safeCoords(GetFinalRenderedCamCoord(), nil) or (feet + vector3(0.0, 0.0, 1.2))
    local rot = GetFinalRenderedCamRot(2)

    rot = vector3(finite(rot.x, 0.0), 0.0, finite(rot.z, 0.0))

    -- Moving or copying something: start a few metres off it, looking at it.
    if target then
        local yaw = math.rad(rot.z)

        pos = target + vector3(math.sin(yaw) * 6.0, -math.cos(yaw) * 6.0, 3.0)
        rot = lookAt(pos, target)
    end

    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, 60.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)

    freecam = { cam = cam, pos = pos, rot = rot }
end

local function stopFreecam()
    if not freecam then return end

    local ped = PlayerPedId()

    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(freecam.cam, true)
    ClearFocus()

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)

    freecam = nil
end

local function flyFreecam(looking)
    if not freecam then return end

    for index = 1, #FLY_CONTROLS do
        DisableControlAction(0, FLY_CONTROLS[index], true)
    end

    local speed = CAM_NORMAL

    if IsDisabledControlPressed(0, 21) then speed = CAM_FAST end
    if IsDisabledControlPressed(0, 36) then speed = CAM_SLOW end

    local rot = freecam.rot

    -- With the cursor up the mouse is for the gizmo, not for looking.
    if looking then
        local lookX = GetDisabledControlNormal(0, 1) * LOOK_SPEED
        local lookY = GetDisabledControlNormal(0, 2) * LOOK_SPEED

        rot = vector3(math.max(-89.0, math.min(89.0, rot.x - lookY)), 0.0, (rot.z - lookX) % 360)
    end

    local yaw, pitch = math.rad(rot.z), math.rad(rot.x)

    local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local right   = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local move    = vector3(0.0, 0.0, 0.0)

    if IsDisabledControlPressed(0, 32) then move = move + forward end
    if IsDisabledControlPressed(0, 33) then move = move - forward end
    if IsDisabledControlPressed(0, 34) then move = move - right end
    if IsDisabledControlPressed(0, 35) then move = move + right end
    if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
    if IsDisabledControlPressed(0, 44) then move = move - vector3(0.0, 0.0, 1.0) end

    local pos = freecam.pos + move * speed

    -- Kept within reach of the player, where the world is loaded.
    local feet = safeCoords(GetEntityCoords(PlayerPedId()), nil)

    if feet and #(pos - feet) > FREECAM_LEASH then
        pos = feet + (pos - feet) / #(pos - feet) * FREECAM_LEASH
    end

    pos = safeCoords(pos, freecam.pos)

    freecam.pos, freecam.rot = pos, rot

    SetCamCoord(freecam.cam, pos.x, pos.y, pos.z)
    SetCamRot(freecam.cam, rot.x, rot.y, rot.z, 2)
    SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
end

-- What the Studio picker moves around: a ped by default (a column's preview_model / preview_from),
-- or a prop (preview_object, made in Object placement below). spawn, rest (where it sits on a
-- ground point), aim (the ground under the cursor), move and destroy.
local function pedBody(preview)
    preview = type(preview) == "table" and preview or {}

    return {
        title   = "Place Ped",
        scene   = type(preview.scene) == "string" and preview.scene or nil,
        spawn   = function(coords, heading)
            preview_ped = spawnPreview(preview.model, preview.scene, coords, heading)
        end,
        rest    = function(ground) return vector3(ground.x, ground.y, ground.z + PED_CENTRE_OFFSET) end,
        aim     = function() return groundUnderCursor() end,
        move    = movePreview,
        destroy = destroyPreview,
    }
end

function groundUnderCursor(ignore, flags)
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
        local camCoords = freecam and freecam.pos or safeCoords(GetGameplayCamCoord(), nil)
        local rotation  = freecam and freecam.rot or GetGameplayCamRot(2)

        if not camCoords then return last_ground end

        local pitch = math.rad(finite(rotation.x, 0.0))
        local yaw   = math.rad(finite(rotation.z, 0.0))
        local cos   = math.abs(math.cos(pitch))

        local direction = vector3(-math.sin(yaw) * cos, math.cos(yaw) * cos, math.sin(pitch))
        local target    = safeCoords(camCoords + direction * (freecam and FREECAM_REACH or RAY_DISTANCE), nil)

        if not target then return last_ground end

        pending_ray = StartShapeTestRay(
            camCoords.x, camCoords.y, camCoords.z,
            target.x, target.y, target.z,
            flags or -1, ignore or preview_ped or PlayerPedId(), 4
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

local function pickPosition(initial, body)
    local ped  = PlayerPedId()
    local here = safeCoords(GetEntityCoords(ped), vector3(0.0, 0.0, 72.0))

    local heading = finite(initial and initial.heading, GetEntityHeading(ped)) % 360
    local start   = safeCoords(initial, here)

    pending_ray = nil
    last_ground = nil

    if body.freecam then startFreecam(safeCoords(initial, nil)) end

    body.spawn(start, heading)

    local state = {
        coords  = start,
        heading = heading,
        drag    = true,
        fine    = false,
        mode    = "simple",
        cursor  = false,
        scene   = body.scene,
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

    -- Legend rows only: the camera reads these keys itself.
    local fly = body.freecam and {
        { key = "WASD", label = "Fly" },
        { key = "SPACE / Q", label = "Up / Down" },
        { key = "SHIFT / CTRL", label = "Fast / Slow" },
    } or {}

    local function with(keys)
        for index = 1, #fly do keys[#keys + 1] = fly[index] end

        return keys
    end

    simple = with({ place, cancel, turnUp, turnDown, toAdvanced })

    advanced = with({
        place, cancel,
        { key = "R", control = 45, label = "Move / Turn", action = function(inner)
            gizmo_mode = gizmo_mode == "translate" and "rotate" or "translate"

            if inner.cursor then pushGizmo(inner) end
        end },
        toggleCursor,
        toSimple,
    })

    return gg.tool.run({
        title = body.title,
        state = state,
        keys  = simple,
        tick  = function(inner)
            inner.fine = IsDisabledControlPressed(0, 21)

            if body.freecam then flyFreecam(not inner.cursor) end

            if inner.drag then
                local ground = body.aim()

                if ground then
                    inner.coords = body.rest(ground)
                end
            end

            local safe = safeCoords(inner.coords, nil)
            if not safe then
                inner.coords = safeCoords(GetEntityCoords(PlayerPedId()), vector3(0.0, 0.0, 72.0))
                return
            end

            inner.coords = safe

            body.move(inner)

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

            body.destroy()
            stopFreecam()
        end,
    })
end

-- MARK: Object placement

-- World and objects: a person or a car is never somewhere to set a prop down.
local OBJECT_FLAGS = 17
local OBJECT_LIFT  = 0.015

-- Keys that could still be down from whatever opened the tool (a prompt, or chat's Enter).
local OPENING_KEYS = { 38, 51, 176, 191, 201 }

local function openingKeyDown()
    for index = 1, #OPENING_KEYS do
        local control = OPENING_KEYS[index]
        if IsControlPressed(0, control) or IsDisabledControlPressed(0, control) then return true end
    end

    return false
end

local preview_object = nil
local preview_parts    = {}
local object_owner     = nil
local object_cancelled = false

local function destroyObject()
    if preview_object and DoesEntityExist(preview_object) then
        DeleteEntity(preview_object)
    end

    for _, part in ipairs(preview_parts) do
        if DoesEntityExist(part) then DeleteEntity(part) end
    end

    preview_object = nil
    preview_parts  = {}
end

local function spawnObject(model, coords, heading, tint)
    local hash = type(model) == "number" and model or joaat(tostring(model))

    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end

    if not HasModelLoaded(hash) then return nil end

    local object = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)

    if not object or object == 0 then return nil end

    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, heading)
    SetEntityAlpha(object, 205, false)

    tint = finite(tint, nil)
    if tint then SetObjectTextureVariation(object, math.floor(tint)) end

    local low = GetModelDimensions(hash)

    return object, finite(low and low.z, 0.0)
end

-- The resting spot within `reach` of the player's centre, the way a server measures it: the
-- further the spot is above or below, the less room there is sideways.
local function withinReach(point, reach, low)
    local centre = safeCoords(GetEntityCoords(PlayerPedId()), nil)
    if not centre then return nil end

    local dz = point.z - centre.z
    if math.abs(dz) >= reach then return nil end

    local dx, dy = point.x - centre.x, point.y - centre.y
    local flat, allowed = math.sqrt(dx * dx + dy * dy), math.sqrt(reach * reach - dz * dz)

    if flat <= allowed then return point end

    local scale = allowed / flat
    local x, y = centre.x + dx * scale, centre.y + dy * scale

    if low then
        local found, z = GetGroundZFor_3dCoord(x, y, point.z + 1.0, false)
        if found then
            local grounded = vector3(x, y, z - low + OBJECT_LIFT)
            if math.abs(grounded.z - centre.z) < reach then return grounded end
        end
    end

    return vector3(x, y, point.z)
end

local function placeObject(options)
    local ped   = PlayerPedId()
    local here  = safeCoords(GetEntityCoords(ped), vector3(0.0, 0.0, 72.0))
    local reach = math.max(0.5, math.min(25.0, finite(options.maxDistance, 3.0)))

    local heading = finite(options.heading, GetEntityHeading(ped)) % 360

    pending_ray = nil
    last_ground = nil

    local object, low = spawnObject(options.model, here, heading, options.tint)
    if not object then return "that model could not be loaded" end

    preview_object = object

    -- Models that make up the same thing (a separate screens model), on the object's own origin.
    for _, model in ipairs(type(options.with) == "table" and options.with or {}) do
        local part = spawnObject(model, here, heading)
        if part then preview_parts[#preview_parts + 1] = part end
    end

    -- Let go of the key that opened this before reading any, so it cannot also place or switch.
    local released = GetGameTimer() + 1000
    repeat Wait(0) until not openingKeyDown() or object_cancelled or GetGameTimer() > released

    local state = {
        coords  = nil,
        heading = heading,
        drag    = true,
        fine    = false,
        mode    = "simple",
        cursor  = false,
    }

    active_state = state

    local place = { key = "ENTER", control = 191, label = options.placeLabel or "Place", action = function(inner)
        if not inner.coords then return end

        inner.placed = { x = inner.coords.x, y = inner.coords.y, z = inner.coords.z, heading = inner.heading }
        inner.done   = true
    end }

    local cancel = { key = "ESC", control = 200, label = "Cancel", cancel = true }
    local back   = { control = 177, cancel = true }

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

    local toAdvanced = { key = "E", control = 38, label = "Gizmo", action = function(inner)
        if not inner.coords then return end

        inner.mode = "advanced"
        inner.drag = false

        gg.tool.setKeys(advanced)
        setCursor(inner, true)
    end }

    local toSimple = { key = "E", control = 38, label = "Aim", action = function(inner)
        inner.mode = "simple"
        inner.drag = true

        setCursor(inner, false)
        gg.tool.setKeys(simple)
    end }

    simple = { place, cancel, back, turnUp, turnDown, toAdvanced }

    advanced = {
        place, cancel, back,
        { key = "R", control = 45, label = "Move / Turn", action = function(inner)
            gizmo_mode = gizmo_mode == "translate" and "rotate" or "translate"

            if inner.cursor then pushGizmo(inner) end
        end },
        { key = "L-ALT", control = 19, label = "Cursor", action = function(inner)
            setCursor(inner, not inner.cursor)
        end },
        toSimple,
    }

    gizmo_mode = "translate"

    gg.tool.run({
        title = type(options.title) == "string" and options.title or "Place Object",
        state = state,
        keys  = simple,
        tick  = function(inner)
            local player = PlayerPedId()

            if object_cancelled or IsEntityDead(player) or IsPedInAnyVehicle(player, false) then
                inner.done = true
                return
            end

            inner.fine = IsDisabledControlPressed(0, 21)

            local target = inner.coords

            if inner.drag then
                local ground = groundUnderCursor(object, OBJECT_FLAGS)
                if ground then target = vector3(ground.x, ground.y, ground.z - low + OBJECT_LIFT) end
            end

            target = target and withinReach(target, reach, inner.drag and low or nil)
            if target then inner.coords = target end

            if not inner.coords then return end

            SetEntityCoordsNoOffset(object, inner.coords.x, inner.coords.y, inner.coords.z, false, false, false)
            SetEntityHeading(object, inner.heading)

            for _, part in ipairs(preview_parts) do
                SetEntityCoordsNoOffset(part, inner.coords.x, inner.coords.y, inner.coords.z, false, false, false)
                SetEntityHeading(part, inner.heading)
            end

            local centre = GetEntityCoords(player)

            gg.tool.setInfo({
                { label = "Distance", value = ("%.1f m"):format(#(vector3(inner.coords.x, inner.coords.y, inner.coords.z) - centre)) },
                { label = "Heading",  value = ("%.0f"):format(finite(inner.heading, 0.0)) },
            }, inner.mode)

            if inner.cursor then pushGizmo(inner) end
        end,
        cleanup = function()
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            SendNUIMessage({ action = "gg_gizmo", data = { ACTIVE = false } })

            destroyObject()
        end,
    })

    return state.placed
end

AddEventHandler("gg_lib:placement:place", function(resource, id, options)
    if type(resource) ~= "string" or id == nil then return end

    TriggerEvent("gg_lib:placement:placeAccepted", resource, id)

    local refusal = (object_owner or gg.tool.isActive()) and "another placement is already open"
        or (type(options) ~= "table" or options.model == nil) and "nothing to place" or nil

    if refusal then
        TriggerEvent("gg_lib:placement:placeResult", resource, id, refusal)
        return
    end

    -- Owned from the moment it is asked for, so a cancel before the tool is up still counts.
    object_owner, object_cancelled = resource, false

    CreateThread(function()
        local answer

        if not object_cancelled then
            GG_PAUSE_GUARD.acquire()

            local ok, result = pcall(placeObject, options)

            -- released first: a cleanup that throws must not keep the pause map shut
            GG_PAUSE_GUARD.release()

            active_state = nil

            gg.tool.abort()
            destroyObject()
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)

            if not ok then
                print(("^1[gg_lib] object placement failed: %s^0"):format(result))
                answer = "the placement tool errored -- see the client console"
            elseif not object_cancelled then
                answer = result
            end
        end

        object_owner = nil

        TriggerEvent("gg_lib:placement:placeResult", resource, id, answer)
    end)
end)

local function cancelFor(resource)
    if resource == nil or resource ~= object_owner then return end

    object_cancelled = true
    gg.tool.abort()
end

AddEventHandler("gg_lib:placement:cancel", cancelFor)
AddEventHandler("onClientResourceStop", cancelFor)

RegisterNUICallback("gg_gizmo_move", function(data, cb)
    if active_state then
        pcall(applyGizmoMove, active_state, data)
    end

    cb({})
end)

-- MARK: Studio picker with a prop

-- A coords column with preview_object = { model, title?, with = { { model, offset = { x, y, z } } } }
-- picks with that prop on the ground instead of a ped: what is being placed, where it will stand.
-- Each `with` part sits at its offset from the model's origin, turned with it, so a thing made of
-- several models (a stand and the wheel on it) shows whole. The picked spot is the model's origin.
local function partOffset(offset)
    if type(offset) ~= "table" and type(offset) ~= "vector3" then return vector3(0.0, 0.0, 0.0) end

    return vector3(
        finite(offset.x or offset[1], 0.0),
        finite(offset.y or offset[2], 0.0),
        finite(offset.z or offset[3], 0.0)
    )
end

local function objectBody(spec)
    local entity, low = nil, 0.0
    local parts = {}

    local function place(coords, heading)
        if entity and DoesEntityExist(entity) then
            SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(entity, heading)
        end

        local h = math.rad(heading)
        local c, s = math.cos(h), math.sin(h)

        for _, part in ipairs(parts) do
            if DoesEntityExist(part.entity) then
                local o = part.offset

                SetEntityCoordsNoOffset(part.entity, coords.x + o.x * c - o.y * s, coords.y + o.x * s + o.y * c, coords.z + o.z, false, false, false)
                SetEntityHeading(part.entity, heading)
            end
        end
    end

    return {
        title   = type(spec.title) == "string" and spec.title or "Place Object",
        spawn   = function(coords, heading)
            entity, low = spawnObject(spec.model, coords, heading)
            low = low or 0.0

            for _, part in ipairs(type(spec.with) == "table" and spec.with or {}) do
                local model = type(part) == "table" and part.model or part
                local object = model and spawnObject(model, coords, heading)

                if object then
                    parts[#parts + 1] = { entity = object, offset = partOffset(type(part) == "table" and part.offset) }
                end
            end

            place(coords, heading)
        end,
        rest    = function(ground) return vector3(ground.x, ground.y, ground.z - low + OBJECT_LIFT) end,
        aim     = function() return groundUnderCursor(entity, OBJECT_FLAGS) end,
        move    = function(state)
            local target = safeCoords(state.coords, nil)
            if target then place(target, finite(state.heading, 0.0) % 360) end
        end,
        destroy = function()
            if entity and DoesEntityExist(entity) then DeleteEntity(entity) end

            for _, part in ipairs(parts) do
                if DoesEntityExist(part.entity) then DeleteEntity(part.entity) end
            end

            entity, parts = nil, {}
        end,
    }
end

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

    local preview = data and data.preview
    local object  = type(preview) == "table" and type(preview.object) == "table" and preview.object.model ~= nil and preview.object or nil
    local body    = object and objectBody(object) or pedBody(preview)

    body.freecam = object and object.freecam == true or nil

    local ok, picked = pcall(pickPosition, data and data.current, body)

    GG_PAUSE_GUARD.release()

    active_state = nil

    gg.tool.abort()
    body.destroy()
    stopFreecam()
    destroyPreview()
    GG_EDITOR_BUCKET.leave()

    SetNuiFocusKeepInput(false)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "settings_placing", data = { PLACING = false } })

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
    stopFreecam()
    destroyPreview()
    destroyObject()
end)

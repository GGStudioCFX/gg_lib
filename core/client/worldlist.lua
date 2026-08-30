
gg = gg or {}
gg.print = gg.print or { error = print, warn = print, log = print }

GG_PAUSE_GUARD = GG_PAUSE_GUARD or { holders = 0 }
GG_PAUSE_GUARD.acquire = GG_PAUSE_GUARD.acquire or function() end
GG_PAUSE_GUARD.release = GG_PAUSE_GUARD.release or function() end

GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }
GG_EDITOR_BUCKET.enter = GG_EDITOR_BUCKET.enter or function() return false end
GG_EDITOR_BUCKET.leave = GG_EDITOR_BUCKET.leave or function() end

local MIN_GAP_FALLBACK = 0.5

local CAM_SLOW = 0.08
local CAM_NORMAL = 0.35
local CAM_FAST = 1.1
local LOOK_SPEED = 6.0

local GHOST_ALPHA = 170
local FINE_TURN = 1.0
local COARSE_TURN = 5.0

local PICK_RADIUS = 2.6

local CORNER_PICK_RADIUS = 1.6

local session = nil

local function finite(number, fallback)
    number = tonumber(number)

    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end

    return number
end

local function pointOf(entry, fallback)
    if type(entry) ~= "table" then return fallback end

    local x = finite(entry.x, nil)
    local y = finite(entry.y, nil)
    local z = finite(entry.z, nil)

    if not x or not y or not z then return fallback end

    return { x = x, y = y, z = z, heading = finite(entry.heading, 0.0) % 360 }
end

local function destroyGhost(ghost)
    if ghost and DoesEntityExist(ghost) then
        SetEntityAsMissionEntity(ghost, true, true)
        DeleteEntity(ghost)
    end
end

local function clearGhosts(state)
    for index = 1, #state.ghosts do
        destroyGhost(state.ghosts[index])
        state.ghosts[index] = nil
    end

    if state.ghost_alpha then
        for index in pairs(state.ghost_alpha) do state.ghost_alpha[index] = nil end
    end
end

local function loadModel(model)
    if gg.util and gg.util.loadModel then return gg.util.loadModel(model) end

    if not IsModelValid(model) then return false end

    RequestModel(model)

    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) do
        Wait(100)

        if GetGameTimer() > timeout then return false end
    end

    return true
end

local function spawnGhost(model, point, lift)
    if not loadModel(model) then return nil end

    local entity = CreateVehicle(GetHashKey(model), point.x, point.y, point.z + (lift or 0.0), point.heading, false, false)

    if not DoesEntityExist(entity) then return nil end

    SetEntityAlpha(entity, GHOST_ALPHA, false)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetVehicleDoorsLocked(entity, 4)
    SetModelAsNoLongerNeeded(GetHashKey(model))

    return entity
end

local function modelLift(model)
    local hash = GetHashKey(model)
    local minimum = GetModelDimensions(hash)

    if not minimum then return 0.0 end

    return math.abs(minimum.z)
end

local function modelFootprint(model)
    local hash = GetHashKey(model)
    local minimum, maximum = GetModelDimensions(hash)

    if not minimum or not maximum then
        return { width = 1.1, length = 2.4 }
    end

    return {
        width  = math.abs(maximum.x - minimum.x) / 2,
        length = math.abs(maximum.y - minimum.y) / 2,
    }
end

local function syncGhost(state, index)
    local ghost = state.ghosts[index]
    local point = state.points[index]

    if not ghost or not point or not DoesEntityExist(ghost) then return end

    SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z + state.lift, false, false, false)
    SetEntityHeading(ghost, point.heading)
end

local function rebuildGhosts(state)
    clearGhosts(state)

    for index = 1, #state.points do
        state.ghosts[index] = spawnGhost(state.model, state.points[index], state.lift)
    end
end

local function bayAxes(heading)
    local radians = math.rad(heading)
    local sin, cos = math.sin(radians), math.cos(radians)

    return { x = cos, y = sin }, { x = -sin, y = cos }  -- right, forward
end

local function dot(a, b)
    return (a.x * b.x) + (a.y * b.y)
end

local function footprintsTouch(a, b, half, padding)
    local aRight, aForward = bayAxes(a.heading)
    local bRight, bForward = bayAxes(b.heading)

    local between = { x = b.x - a.x, y = b.y - a.y }

    for _, axis in ipairs({ aRight, aForward, bRight, bForward }) do
        local reachA = (half.width * math.abs(dot(aRight, axis))) + (half.length * math.abs(dot(aForward, axis)))
        local reachB = (half.width * math.abs(dot(bRight, axis))) + (half.length * math.abs(dot(bForward, axis)))

        if math.abs(dot(between, axis)) > (reachA + reachB + padding) then
            return false
        end
    end

    return true
end

local function conflictWith(state, point, ignoreIndex)
    if state.polygon then return nil end

    for index = 1, #state.points do
        if index ~= ignoreIndex then
            if footprintsTouch(point, state.points[index], state.half, state.padding) then
                return index
            end
        end
    end

    return nil
end

local function startCamera(state)
    GG_EDITOR_BUCKET.enter()

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local rotation = GetGameplayCamRot(2)

    state.cam_pos = vector3(coords.x, coords.y, coords.z + 1.2)
    state.cam_rot = vector3(rotation.x, rotation.y, rotation.z)

    state.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    SetCamCoord(state.cam, state.cam_pos.x, state.cam_pos.y, state.cam_pos.z)
    SetCamRot(state.cam, state.cam_rot.x, state.cam_rot.y, state.cam_rot.z, 2)
    SetCamFov(state.cam, 60.0)
    SetCamActive(state.cam, true)
    RenderScriptCams(true, true, 400, true, true)

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
end

local function stopCamera(state)
    local ped = PlayerPedId()

    GG_EDITOR_BUCKET.leave()

    RenderScriptCams(false, true, 400, true, true)

    if state.cam then
        DestroyCam(state.cam, true)
        state.cam = nil
    end

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
end

local function moveCamera(state)
    local speed = CAM_NORMAL

    if IsDisabledControlPressed(0, 21) then speed = CAM_FAST end      -- shift
    if IsDisabledControlPressed(0, 36) then speed = CAM_SLOW end      -- ctrl

    local lookX = GetDisabledControlNormal(0, 1) * LOOK_SPEED
    local lookY = GetDisabledControlNormal(0, 2) * LOOK_SPEED

    local pitch = math.max(-89.0, math.min(89.0, state.cam_rot.x - lookY))
    local yaw = (state.cam_rot.z - lookX) % 360

    state.cam_rot = vector3(pitch, 0.0, yaw)

    local yawRad = math.rad(yaw)
    local pitchRad = math.rad(pitch)

    local forward = vector3(-math.sin(yawRad) * math.cos(pitchRad), math.cos(yawRad) * math.cos(pitchRad), math.sin(pitchRad))
    local right = vector3(math.cos(yawRad), math.sin(yawRad), 0.0)

    local move = vector3(0.0, 0.0, 0.0)

    if IsDisabledControlPressed(0, 32) then move = move + forward end
    if IsDisabledControlPressed(0, 33) then move = move - forward end
    if IsDisabledControlPressed(0, 34) then move = move - right end
    if IsDisabledControlPressed(0, 35) then move = move + right end
    if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end   -- space
    if IsDisabledControlPressed(0, 44) then move = move - vector3(0.0, 0.0, 1.0) end   -- Q

    state.cam_pos = state.cam_pos + (move * speed)

    SetCamCoord(state.cam, state.cam_pos.x, state.cam_pos.y, state.cam_pos.z)
    SetCamRot(state.cam, state.cam_rot.x, state.cam_rot.y, state.cam_rot.z, 2)

    SetFocusPosAndVel(state.cam_pos.x, state.cam_pos.y, state.cam_pos.z, 0.0, 0.0, 0.0)
end

local function cameraForward(state)
    local yawRad = math.rad(state.cam_rot.z)
    local pitchRad = math.rad(state.cam_rot.x)

    return vector3(-math.sin(yawRad) * math.cos(pitchRad), math.cos(yawRad) * math.cos(pitchRad), math.sin(pitchRad))
end

local AIM_DISTANCE = 120.0
local BEAM_START = 0.45

local function bayUnderBeam(state, origin, forward, reach)
    local reachRadius = state.polygon and CORNER_PICK_RADIUS or PICK_RADIUS
    local best, bestGap = nil, reachRadius

    for index = 1, #state.points do
        if index ~= state.selected then
            local point = state.points[index]
            local toPoint = vector3(point.x, point.y, point.z) - origin
            local along = (toPoint.x * forward.x) + (toPoint.y * forward.y) + (toPoint.z * forward.z)

            if along > 0.0 and along <= (reach + reachRadius) then
                local nearest = origin + (forward * along)
                local gap = #(vector3(point.x, point.y, point.z) - nearest)

                if gap < bestGap then
                    best, bestGap = index, gap
                end
            end
        end
    end

    return best
end

local function aim(state)
    local forward = cameraForward(state)
    local from = state.cam_pos + (forward * BEAM_START)
    local to = state.cam_pos + (forward * AIM_DISTANCE)

    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, 0, 4)
    local _, hit, coords = GetShapeTestResult(ray)

    local landing

    if hit == 1 then
        landing = vector3(coords.x, coords.y, coords.z)
    else
        local found, z = GetGroundZFor_3dCoord(to.x, to.y, to.z + 25.0, false)

        landing = vector3(to.x, to.y, found and z or to.z)
    end

    return landing, bayUnderBeam(state, from, forward, #(landing - from))
end

local ZONE_HEIGHT = 4.0

local function drawPolygon(state)
    local total = #state.points

    if total == 0 then return end

    for index = 1, total do
        local corner = state.points[index]
        local next_corner = state.points[(index % total) + 1]
        local focused = index == state.selected or index == state.highlight

        local r, g, b = 198, 148, 255

        if index == state.selected then
            r, g, b = 255, 255, 255
        end

        local edge = focused and 235 or 150
        local top = corner.z + ZONE_HEIGHT

        if total > 1 then
            DrawLine(corner.x, corner.y, corner.z, next_corner.x, next_corner.y, next_corner.z, r, g, b, edge)
            DrawLine(corner.x, corner.y, top, next_corner.x, next_corner.y, next_corner.z + ZONE_HEIGHT, r, g, b, 90)
        end

        DrawLine(corner.x, corner.y, corner.z, corner.x, corner.y, top, r, g, b, 110)

        DrawMarker(
            28,
            corner.x, corner.y, corner.z + 0.12,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            focused and 0.35 or 0.22, focused and 0.35 or 0.22, focused and 0.35 or 0.22,
            r, g, b, focused and 220 or 150,
            false, false, 2, false, nil, nil, false
        )

        if focused then
            DrawMarker(
                0,
                corner.x, corner.y, corner.z + 2.2,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.45, 0.45, 0.4,
                r, g, b, 220,
                true, true, 2, nil, nil, nil, false
            )
        end
    end
end

local function drawBayMarkers(state)
    for index = 1, #state.points do
        local point = state.points[index]
        local held = index == state.selected
        local focused = index == state.highlight

        local r, g, b = 198, 148, 255
        local alpha = 90

        if held then
            alpha = 220
            if state.blocked then r, g, b = 255, 75, 43 end
        elseif focused then
            r, g, b = 255, 255, 255
            alpha = 220
        end

        local right, forward = bayAxes(point.heading)
        local halfWidth = state.half.width + (state.padding / 2)
        local halfLength = state.half.length + (state.padding / 2)

        local function corner(sideways, lengthways)
            return vector3(
                point.x + (right.x * halfWidth * sideways) + (forward.x * halfLength * lengthways),
                point.y + (right.y * halfWidth * sideways) + (forward.y * halfLength * lengthways),
                point.z + 0.06
            )
        end

        local a1, a2, a3, a4 = corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)
        local edge = (held or focused) and 220 or 120

        DrawLine(a1.x, a1.y, a1.z, a2.x, a2.y, a2.z, r, g, b, edge)
        DrawLine(a2.x, a2.y, a2.z, a3.x, a3.y, a3.z, r, g, b, edge)
        DrawLine(a3.x, a3.y, a3.z, a4.x, a4.y, a4.z, r, g, b, edge)
        DrawLine(a4.x, a4.y, a4.z, a1.x, a1.y, a1.z, r, g, b, edge)

        local nose = corner(0, 1)
        DrawLine(nose.x, nose.y, nose.z, nose.x + forward.x * 0.8, nose.y + forward.y * 0.8, nose.z, r, g, b, edge)

        if held or focused then
            DrawMarker(
                0,
                point.x, point.y, point.z + 2.7,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.6, 0.6, 0.5,
                r, g, b, alpha,
                true, true, 2, nil, nil, nil, false
            )
        end
    end
end

local function drawAim(state)
    if not state.aim_point then return end

    local from = state.cam_pos + (cameraForward(state) * BEAM_START)
    local point = state.aim_point

    local r, g, b = 198, 148, 255

    if state.blocked then
        r, g, b = 255, 75, 43
    elseif state.highlight and not state.selected then
        r, g, b = 255, 255, 255
    end

    DrawLine(from.x, from.y, from.z, point.x, point.y, point.z, r, g, b, 190)

    DrawMarker(
        28,
        point.x, point.y, point.z + 0.05,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.22, 0.22, 0.22,
        r, g, b, 180,
        false, false, 2, false,
        nil, nil, false
    )
end

local function refreshInfo(state)
    local noun = state.polygon and "Corner" or "Bay"

    local rows = {
        { label = state.polygon and "Corners" or "Bays", value = tostring(#state.points) },
    }

    if state.polygon then
        rows[#rows + 1] = { label = "Zone", value = #state.points >= 3 and "Closed" or "Needs 3+" }
    else
        rows[#rows + 1] = { label = "Gap", value = ("%.1fm"):format(state.padding) }
    end

    if state.selected then
        rows[#rows + 1] = { label = "Moving", value = ("%s %d"):format(noun, state.selected) }

        if not state.polygon then
            rows[#rows + 1] = { label = "Heading", value = ("%d deg"):format(math.floor(state.points[state.selected].heading + 0.5)) }
            rows[#rows + 1] = { label = "Status", value = state.blocked and "Too close" or "Clear" }
        end
    elseif state.highlight then
        rows[#rows + 1] = { label = "Aiming", value = ("%s %d"):format(noun, state.highlight) }
    end

    gg.tool.setInfo(rows, state.selected and "editing" or "browse")
end

local function editPoints(list, preview, minGap, mode)
    local polygon = mode == "polygon"

    local state = {
        polygon = polygon,
        points = {},
        ghosts = {},
        ghost_alpha = {},
        model = (type(preview) == "table" and type(preview.model) == "string" and preview.model) or "taxi",
        padding = finite(minGap, MIN_GAP_FALLBACK),
        half = { width = 1.1, length = 2.4 },
        selected = nil,
        highlight = nil,
        blocked = false,
        fine = false,
        lift = 0.0,
    }

    for index, entry in ipairs(list or {}) do
        local point = pointOf(entry, nil)
        if point then state.points[#state.points + 1] = point end
    end

    session = state

    startCamera(state)

    if not polygon then
        loadModel(state.model)
        state.lift = modelLift(state.model)
        state.half = modelFootprint(state.model)

        rebuildGhosts(state)
    end

    local browse, editing

    local save = { key = "ENTER", control = 191, label = "Save", finish = function(inner)
        if not inner.polygon then return inner.points end

        local corners = {}

        for index = 1, #inner.points do
            local corner = inner.points[index]

            corners[index] = { x = corner.x, y = corner.y, z = corner.z }
        end

        return corners
    end }

    local cancel = { key = "ESC", control = 200, label = "Cancel", cancel = true }

    local grab = { key = "E", control = 38, label = "Edit", action = function(inner)
        if not inner.highlight then return end

        inner.selected = inner.highlight
        inner.blocked = false

        gg.tool.setKeys(editing)
    end }

    local drop = { key = "E", control = 38, label = "Place", action = function(inner)
        if not inner.selected then return end
        if inner.blocked then return end

        inner.selected = nil

        gg.tool.setKeys(browse)
    end }

    local add = { key = "G", control = 47, label = polygon and "New Corner" or "New Bay", action = function(inner)
        local landing = inner.aim_point or aim(inner)
        local point = { x = landing.x, y = landing.y, z = landing.z, heading = inner.cam_rot.z % 360 }

        if conflictWith(inner, point, nil) then return end

        inner.points[#inner.points + 1] = point

        if not inner.polygon then
            inner.ghosts[#inner.points] = spawnGhost(inner.model, point, inner.lift)
        end

        inner.selected = #inner.points

        gg.tool.setKeys(editing)
    end }

    local remove = { key = "DEL", control = 178, label = "Remove", action = function(inner)
        local target = inner.selected or inner.highlight
        if not target then return end

        destroyGhost(inner.ghosts[target])

        table.remove(inner.points, target)
        table.remove(inner.ghosts, target)

        for index in pairs(inner.ghost_alpha) do inner.ghost_alpha[index] = nil end

        inner.selected = nil
        inner.highlight = nil

        gg.tool.setKeys(browse)
    end }

    local turnUp = { control = 15, repeatable = false, action = function(inner)
        if not inner.selected then return end

        inner.points[inner.selected].heading = (inner.points[inner.selected].heading + (inner.fine and FINE_TURN or COARSE_TURN)) % 360
        syncGhost(inner, inner.selected)
    end }

    local turnDown = { key = "Scroll", control = 14, label = "Turn", action = function(inner)
        if not inner.selected then return end

        inner.points[inner.selected].heading = (inner.points[inner.selected].heading - (inner.fine and FINE_TURN or COARSE_TURN)) % 360
        syncGhost(inner, inner.selected)
    end }

    browse = { save, cancel, grab, add, remove }

    editing = polygon and { drop, cancel, remove } or { drop, cancel, turnUp, turnDown, remove }

    local result = gg.tool.run({
        title = polygon and "Zone Corners" or "Rental Bays",
        mode  = "browse",
        state = state,
        keys  = browse,
        tick  = function(inner)
            inner.fine = IsDisabledControlPressed(0, 19)

            moveCamera(inner)

            local landing, overGhost = aim(inner)

            inner.aim_point = landing

            if inner.selected then
                local point = inner.points[inner.selected]

                point.x, point.y, point.z = landing.x, landing.y, landing.z

                if not inner.polygon then syncGhost(inner, inner.selected) end

                inner.blocked = conflictWith(inner, point, inner.selected) ~= nil
                inner.highlight = nil
            else
                inner.highlight = overGhost
                inner.blocked = false
            end

            if inner.polygon then
                drawPolygon(inner)
                drawAim(inner)
                refreshInfo(inner)

                return
            end

            drawBayMarkers(inner)
            drawAim(inner)

            local focus = inner.selected or inner.highlight

            if focus then
                if inner.selected and inner.blocked then
                    SetEntityDrawOutlineColor(255, 75, 43, 255)
                elseif inner.selected then
                    SetEntityDrawOutlineColor(198, 148, 255, 255)
                else
                    SetEntityDrawOutlineColor(255, 255, 255, 255)
                end
            end

            for index = 1, #inner.ghosts do
                local ghost = inner.ghosts[index]

                if ghost and DoesEntityExist(ghost) then
                    SetEntityDrawOutline(ghost, index == focus)

                    local alpha = index == focus and 255 or GHOST_ALPHA

                    if inner.ghost_alpha[index] ~= alpha then
                        SetEntityAlpha(ghost, alpha, false)
                        inner.ghost_alpha[index] = alpha
                    end
                end
            end

            refreshInfo(inner)
        end,
        cleanup = function(inner)
            clearGhosts(inner)
            stopCamera(inner)
            ClearFocus()
        end,
    })

    session = nil

    return result
end

RegisterNUICallback("settings_edit_points", function(data, cb)
    if not gg.tool or not gg.tool.run then
        cb({ ok = false })
        return
    end

    if gg.tool.isActive() then
        cb({ ok = false })
        return
    end

    GG_PAUSE_GUARD.acquire()

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "settings_placing", data = { PLACING = true } })

    local ok, picked = pcall(editPoints, data and data.current, data and data.preview, data and data.min_gap, data and data.mode)

    gg.tool.abort()

    if session then
        clearGhosts(session)
        stopCamera(session)
        ClearFocus()
        session = nil
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "settings_placing", data = { PLACING = false } })

    GG_PAUSE_GUARD.release()

    if not ok then
        gg.print.error(("Point editor failed: %s"):format(picked))
        cb({ ok = false })
        return
    end

    cb({ ok = picked ~= nil, POINTS = picked })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= "gg_lib" then return end

    if session then
        clearGhosts(session)
        stopCamera(session)
        ClearFocus()
    end
end)

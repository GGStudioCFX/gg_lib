
local RESOURCE = GetCurrentResourceName()

local DUI = {
    width  = 4096,
    height = 2048,
    txd    = "gg_waypoint",
}

local BUSY_COUNT = 12

local STYLES = {
    race = { label = "CHECKPOINT", icon = "fa-flag-checkered" },
    taxi = { label = "DROP OFF",   icon = "fa-user" },
}

local DEFAULT_STYLE = "race"

local TUNING = {
    label            = "CHECKPOINT",
    render_distance  = 10000.0,
    update_interval  = 125,
    miles_from_yards = 600.0,

    visibility_max_lift           = 4200.0,
    visibility_search_attempts    = 14,
    visibility_search_interval    = 250,
    visibility_ray_flags          = 1,
    visibility_ignore_entity_hits = true,
    visibility_blocked_required   = 2,
    visibility_single_block_yards = 220.0,
    visibility_near_hit_distance  = 25.0,
    visibility_near_hit_ratio     = 0.08,
    visibility_samples = {
        { x = 0.0, y = 0.58 },
        { x = 0.0, y = 0.2 },
    },

    flip_horizontal = true,
    ground_line     = true,

    width_curve = {
        { yards = 0.0, value = 4.0 },
        { yards = 100.0, value = 18.0 },
        { yards = 1000.0, value = 78.0 },
        { yards = 2000.0, value = 150.0 },
        { yards = 3500.0, value = 275.0 },
        { yards = 7040.0, value = 520.0 },
    },
    lift_curve = {
        { yards = 0.0, value = 2.0 },
        { yards = 75.0, value = 12.0 },
        { yards = 150.0, value = 24.0 },
        { yards = 225.0, value = 42.0 },
        { yards = 300.0, value = 72.0 },
        { yards = 400.0, value = 54.0 },
        { yards = 600.0, value = 78.0 },
        { yards = 800.0, value = 118.0 },
        { yards = 1000.0, value = 155.0 },
        { yards = 1760.0, value = 210.0 },
        { yards = 2200.0, value = 260.0 },
        { yards = 2700.0, value = 380.0 },
        { yards = 3200.0, value = 520.0 },
        { yards = 3520.0, value = 620.0 },
        { yards = 5000.0, value = 620.0 },
    },
    visibility_max_lift_curve = {
        { yards = 0.0, value = 90.0 },
        { yards = 300.0, value = 130.0 },
        { yards = 400.0, value = 120.0 },
        { yards = 600.0, value = 155.0 },
        { yards = 800.0, value = 205.0 },
        { yards = 1000.0, value = 240.0 },
        { yards = 1760.0, value = 360.0 },
        { yards = 2200.0, value = 520.0 },
        { yards = 3200.0, value = 900.0 },
        { yards = 3520.0, value = 1200.0 },
        { yards = 5280.0, value = 2600.0 },
        { yards = 7040.0, value = 4200.0 },
    },
    visibility_block_delay_curve = {
        { yards = 0.0, value = 120.0 },
        { yards = 200.0, value = 150.0 },
        { yards = 400.0, value = 260.0 },
        { yards = 1000.0, value = 700.0 },
    },
    visibility_clear_delay_curve = {
        { yards = 0.0, value = 180.0 },
        { yards = 200.0, value = 240.0 },
        { yards = 400.0, value = 420.0 },
        { yards = 1000.0, value = 1200.0 },
    },
    visibility_lift_up_speed_curve = {
        { yards = 0.0, value = 540.0 },
        { yards = 200.0, value = 480.0 },
        { yards = 400.0, value = 360.0 },
        { yards = 1000.0, value = 220.0 },
    },
    visibility_lift_down_speed_curve = {
        { yards = 0.0, value = 360.0 },
        { yards = 200.0, value = 320.0 },
        { yards = 400.0, value = 220.0 },
        { yards = 1000.0, value = 95.0 },
    },
    visibility_near_block_raise_curve = {
        { yards = 0.0, value = 36.0 },
        { yards = 150.0, value = 82.0 },
        { yards = 300.0, value = 96.0 },
        { yards = 1000.0, value = 120.0 },
        { yards = 3520.0, value = 140.0 },
        { yards = 7040.0, value = 220.0 },
    },
    text_scale_curve = {
        { yards = 0.0, value = 1.0 },
        { yards = 1000.0, value = 1.05 },
        { yards = 1760.0, value = 1.32 },
        { yards = 2000.0, value = 1.36 },
        { yards = 3500.0, value = 1.69 },
        { yards = 7040.0, value = 2.1 },
    },

    size_tween_speed = 52.0,
    text_tween_speed = 1.2,
}

local waypoints = {}   -- key -> waypoint
local routes    = {}   -- key -> { ids = {}, activeId, activeIndex }
local live      = 0
local warned    = false
local drawing   = false

local styleDefaults = {}

local function refreshStyleDefaults()
    local ok, stored = pcall(GGCallback.await, "gg_lib:waypoints:defaults")

    if ok and type(stored) == "table" then styleDefaults = stored end
end

local function warn(message)
    print(("^3[gg_lib] %s^0"):format(message))
end

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end

    return value
end

local function lerp(from, to, progress)
    return from + ((to - from) * progress)
end

local function interpolateCurve(curve, yards)
    if not curve or #curve == 0 then return 0.0 end
    if yards <= curve[1].yards then return curve[1].value end

    for index = 2, #curve do
        local previous = curve[index - 1]
        local current  = curve[index]

        if yards <= current.yards then
            local span = current.yards - previous.yards

            if span <= 0.0 then return current.value end

            return lerp(previous.value, current.value, (yards - previous.yards) / span)
        end
    end

    return curve[#curve].value
end

local function moveTowards(current, target, speed)
    if current == target then return current end

    local step = speed * GetFrameTime()

    if math.abs(target - current) <= step then return target end

    return current + ((target > current and 1.0 or -1.0) * step)
end

local function distanceBetween(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z

    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function unitSystem()
    local stored = GlobalState.gg_units

    return stored == "imperial" and "imperial" or "metric"
end

local function formatDistance(distance)
    distance = math.max(0, distance)

    if unitSystem() == "imperial" then
        local yards = distance * 1.09361

        if yards >= TUNING.miles_from_yards then
            return math.floor((yards / 1760.0) * 10.0 + 0.5) / 10.0, "MI"
        end

        return math.floor(yards + 0.5), "YD"
    end

    if distance >= TUNING.miles_from_yards * 0.9144 then
        return math.floor((distance / 1000.0) * 10.0 + 0.5) / 10.0, "KM"
    end

    return math.floor(distance + 0.5), "M"
end

local function duiUrl(style)
    return ("nui://%s/web/dist/index.html?dui=waypoint&style=%s"):format(RESOURCE, style)
end

local dictionaries = {}
local textureCount = 0

local function createTexture(slug, style)
    local dui    = CreateDui(duiUrl(style), DUI.width, DUI.height)
    local handle = GetDuiHandle(dui)
    local name   = ("%s_%s"):format(DUI.txd, slug)

    if not dictionaries[name] then
        dictionaries[name] = CreateRuntimeTxd(name)
    end

    textureCount = textureCount + 1

    local txn = ("waypoint_%s_%d"):format(slug, textureCount)

    CreateRuntimeTextureFromDuiHandle(dictionaries[name], txn, handle)

    return dui, name, txn
end

local function sendUpdate(waypoint, distance)
    if not waypoint.dui then return end

    local value, unit = formatDistance(distance)

    SendDuiMessage(waypoint.dui, json.encode({
        action = "waypoint_update",
        data   = {
            distance = value,
            unit     = unit,
            label    = waypoint.label,
            style    = waypoint.style,
            icon     = waypoint.icon,
        },
    }))
end

local function billboardBasis(center)
    local cam    = GetFinalRenderedCamCoord()
    local dx, dy = cam.x - center.x, cam.y - center.y
    local length = math.sqrt((dx * dx) + (dy * dy))

    if length < 0.001 then
        return vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0)
    end

    return vec3(dy / length, -dx / length, 0.0), vec3(0.0, 0.0, 1.0)
end

local function pointFrom(center, right, up, rightScale, upScale)
    return vec3(
        center.x + (right.x * rightScale) + (up.x * upScale),
        center.y + (right.y * rightScale) + (up.y * upScale),
        center.z + (right.z * rightScale) + (up.z * upScale)
    )
end

local probeRay = StartExpensiveSynchronousShapeTestLosProbe or StartShapeTestRay

local function cameraBlockInfo(coords)
    local cam = GetFinalRenderedCamCoord()

    local ray = probeRay(
        cam.x, cam.y, cam.z,
        coords.x, coords.y, coords.z,
        TUNING.visibility_ray_flags,
        PlayerPedId(),
        7
    )

    local result, hit, hitCoords, _, entityHit = GetShapeTestResult(ray)

    if TUNING.visibility_ignore_entity_hits and entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        return false, false
    end

    if result ~= 2 or hit ~= 1 then return false, false end

    local total = math.max(distanceBetween(cam, coords), 0.001)
    local reach = hitCoords and distanceBetween(cam, hitCoords) or total

    return true, reach <= TUNING.visibility_near_hit_distance or (reach / total) <= TUNING.visibility_near_hit_ratio
end

local function sampleCoords(coords, lift, width, height, sample)
    local center    = vec3(coords.x, coords.y, coords.z + lift + (height * 0.5))
    local right, up = billboardBasis(center)

    return pointFrom(center, right, up, (sample.x or 0.0) * width * 0.5, ((sample.y or 0.5) - 0.5) * height)
end

local function visibilityState(coords, lift, width, height, yards)
    local blocked, near = 0, false
    local required = (yards and yards <= TUNING.visibility_single_block_yards) and 1 or TUNING.visibility_blocked_required

    for _, sample in ipairs(TUNING.visibility_samples) do
        local isBlocked, isNear = cameraBlockInfo(sampleCoords(coords, lift, width, height, sample))

        if isBlocked then
            blocked = blocked + 1
            near = near or isNear
        end
    end

    return blocked >= required, near
end

local function clearLift(coords, lift, width, height, maxLift, yards)
    local low, high, best = lift, maxLift or TUNING.visibility_max_lift, nil

    if not visibilityState(coords, lift, width, height, yards) then return lift end
    if visibilityState(coords, high, width, height, yards) then return high end

    for _ = 1, TUNING.visibility_search_attempts do
        local mid = (low + high) * 0.5

        if visibilityState(coords, mid, width, height, yards) then
            low = mid
        else
            best = mid
            high = mid
        end
    end

    return best or high
end

local function resolveLift(waypoint, baseLift, width, height, maxLift, yards)
    local now = GetGameTimer()

    maxLift = math.max(baseLift, maxLift or TUNING.visibility_max_lift)
    yards = yards or 0.0

    local blockDelay   = interpolateCurve(TUNING.visibility_block_delay_curve, yards)
    local clearDelay   = interpolateCurve(TUNING.visibility_clear_delay_curve, yards)
    local upSpeed      = interpolateCurve(TUNING.visibility_lift_up_speed_curve, yards)
    local downSpeed    = interpolateCurve(TUNING.visibility_lift_down_speed_curve, yards)
    local nearRaiseCap = interpolateCurve(TUNING.visibility_near_block_raise_curve, yards)

    local blocked, near = visibilityState(waypoint.coords, baseLift, width, height, yards)

    if near then maxLift = math.min(maxLift, baseLift + nearRaiseCap) end

    waypoint.currentLift = math.max(waypoint.currentLift or baseLift, baseLift)
    waypoint.targetLift  = clamp(waypoint.targetLift or baseLift, baseLift, maxLift)

    if blocked then
        waypoint.clearSince   = nil
        waypoint.blockedSince = waypoint.blockedSince or now

        if now - waypoint.blockedSince >= blockDelay and now >= (waypoint.nextSearch or 0) then
            waypoint.nextSearch = now + TUNING.visibility_search_interval
            waypoint.targetLift = clearLift(waypoint.coords, baseLift, width, height, maxLift, yards)
        end
    else
        waypoint.blockedSince = nil
        waypoint.clearSince   = waypoint.clearSince or now
        waypoint.nextSearch   = nil

        if now - waypoint.clearSince >= clearDelay then
            waypoint.targetLift = baseLift
        end
    end

    waypoint.targetLift  = clamp(waypoint.targetLift, baseLift, maxLift)
    waypoint.currentLift = moveTowards(
        waypoint.currentLift,
        waypoint.targetLift,
        waypoint.targetLift > waypoint.currentLift and upSpeed or downSpeed
    )

    return waypoint.currentLift
end

local function drawBillboard(waypoint, distance)
    local yards = distance * 1.09361

    waypoint.targetTextScale  = interpolateCurve(TUNING.text_scale_curve, yards)
    waypoint.currentTextScale = moveTowards(waypoint.currentTextScale or 1.0, waypoint.targetTextScale, TUNING.text_tween_speed)

    local targetWidth = interpolateCurve(TUNING.width_curve, yards) * waypoint.currentTextScale

    waypoint.currentWidth = moveTowards(waypoint.currentWidth or targetWidth, targetWidth, TUNING.size_tween_speed)

    local width   = waypoint.currentWidth
    local height  = width * (DUI.height / DUI.width)
    local lift    = interpolateCurve(TUNING.lift_curve, yards)
    local maxLift = interpolateCurve(TUNING.visibility_max_lift_curve, yards)

    local resolved  = resolveLift(waypoint, lift, width, height, maxLift, yards)
    local center    = vec3(waypoint.coords.x, waypoint.coords.y, waypoint.coords.z + resolved + (height * 0.5))
    local right, up = billboardBasis(center)

    local halfWidth, halfHeight = width * 0.5, height * 0.5

    local topLeft     = pointFrom(center, right, up, -halfWidth, halfHeight)
    local topRight    = pointFrom(center, right, up, halfWidth, halfHeight)
    local bottomLeft  = pointFrom(center, right, up, -halfWidth, -halfHeight)
    local bottomRight = pointFrom(center, right, up, halfWidth, -halfHeight)

    local tlU, tlV, trU, trV, blU, blV, brU, brV = 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0

    if TUNING.flip_horizontal then
        tlU, tlV, trU, trV, blU, blV, brU, brV = 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0
    end

    if waypoint.groundLine then
        local foot = pointFrom(center, right, up, 0.0, -halfHeight)

        DrawLine(foot.x, foot.y, foot.z, waypoint.coords.x, waypoint.coords.y, waypoint.coords.z, 255, 255, 255, 170)
    end

    DrawSpritePoly(
        topLeft.x, topLeft.y, topLeft.z,
        topRight.x, topRight.y, topRight.z,
        bottomLeft.x, bottomLeft.y, bottomLeft.z,
        255, 255, 255, 255,
        waypoint.txd, waypoint.txn,
        tlU, tlV, 1.0,
        trU, trV, 1.0,
        blU, blV, 1.0
    )

    DrawSpritePoly(
        topRight.x, topRight.y, topRight.z,
        bottomRight.x, bottomRight.y, bottomRight.z,
        bottomLeft.x, bottomLeft.y, bottomLeft.z,
        255, 255, 255, 255,
        waypoint.txd, waypoint.txn,
        trU, trV, 1.0,
        brU, brV, 1.0,
        blU, blV, 1.0
    )
end

local function ensureDrawing()
    if drawing then return end

    drawing = true

    CreateThread(function()
        while next(waypoints) do
            local ped = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer()

            for _, waypoint in pairs(waypoints) do
                local distance = #(ped - waypoint.coords)

                if waypoint.visible and distance <= waypoint.renderDistance then
                    if now >= waypoint.nextUpdate then
                        sendUpdate(waypoint, distance)
                        waypoint.nextUpdate = now + TUNING.update_interval
                    end

                    drawBillboard(waypoint, distance)
                end
            end

            Wait(0)
        end

        drawing = false
    end)
end

local function normalizeId(id)
    if id == nil then return nil end

    return tostring(id)
end

local function normalizeCoords(coords)
    if not coords then return nil end
    if coords.x == nil or coords.y == nil or coords.z == nil then return nil end

    return vec3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

local function keyOf(owner, id)
    return ("%s:%s"):format(owner, id)
end

local function removeKey(key)
    local waypoint = waypoints[key]
    if not waypoint then return false end

    if waypoint.dui then DestroyDui(waypoint.dui) end

    waypoints[key] = nil
    live = live - 1

    for _, route in pairs(routes) do
        route.ids[key] = nil

        if route.activeId == key then
            route.activeId    = nil
            route.activeIndex = nil
        end
    end

    return true
end

local function create(owner, data)
    local id     = normalizeId(data and data.id)
    local coords = normalizeCoords(data and data.coords)

    if not (id and coords) then return false end

    local key = keyOf(owner, id)

    removeKey(key)

    local style  = STYLES[data.style] and data.style or DEFAULT_STYLE
    local stored = styleDefaults[style] or {}

    local slug = ("%s_%s"):format(owner, id):gsub("[^%w_]", "_")
    local dui, txd, txn = createTexture(slug, style)

    local groundLine = data.ground_line

    if groundLine == nil then groundLine = stored.ground_line end
    if groundLine == nil then groundLine = TUNING.ground_line end

    waypoints[key] = {
        id             = id,
        owner          = owner,
        coords         = coords,
        style          = style,
        icon           = data.icon or STYLES[style].icon,
        label          = data.label or stored.label or STYLES[style].label,
        renderDistance = tonumber(data.render_distance) or tonumber(stored.render_distance) or TUNING.render_distance,
        groundLine     = groundLine == true,
        visible        = data.visible ~= false,
        meta           = data.meta,
        dui            = dui,
        txd            = txd,
        txn            = txn,
        nextUpdate     = 0,
    }

    live = live + 1

    if live > BUSY_COUNT and not warned then
        warned = true
        warn(("%d waypoints are placed at once. Each owns a %dx%d texture, so this is a lot of video memory -- remove the ones that are finished."):format(live, DUI.width, DUI.height))
    end

    ensureDrawing()

    return true
end

local function update(owner, id, data)
    local waypoint = waypoints[keyOf(owner, normalizeId(id) or "")]

    if not (waypoint and type(data) == "table") then return false end

    if data.coords then
        local coords = normalizeCoords(data.coords)

        if coords then
            waypoint.coords = coords

            waypoint.currentLift, waypoint.targetLift = nil, nil
            waypoint.currentWidth = nil
            waypoint.currentTextScale, waypoint.targetTextScale = nil, nil
        end
    end

    if data.label ~= nil then
        waypoint.label = data.label
        waypoint.nextUpdate = 0
    end

    if data.style ~= nil and STYLES[data.style] then
        waypoint.style = data.style
        waypoint.icon = data.icon or STYLES[data.style].icon
        waypoint.nextUpdate = 0
    end

    if data.icon ~= nil then
        waypoint.icon = data.icon
        waypoint.nextUpdate = 0
    end

    if data.ground_line ~= nil then waypoint.groundLine = data.ground_line == true end

    if data.render_distance ~= nil then
        waypoint.renderDistance = tonumber(data.render_distance) or waypoint.renderDistance
    end

    if data.visible ~= nil then waypoint.visible = data.visible == true end
    if data.meta ~= nil then waypoint.meta = data.meta end

    return true
end

local function routeKey(owner, routeId)
    return ("%s:%s"):format(owner, normalizeId(routeId) or "")
end

local function getRoute(owner, routeId)
    local key = routeKey(owner, routeId)

    routes[key] = routes[key] or { ids = {}, activeId = nil, activeIndex = nil }

    return routes[key], key
end

local function setRoutePoint(owner, routeId, index, coords, options)
    if not (routeId and coords) then return false end

    options = options or {}

    local route = getRoute(owner, routeId)
    local id    = options.id or ("route_%s_%s"):format(normalizeId(routeId), index or "active")
    local key   = keyOf(owner, id)

    if route.activeId and route.activeId ~= key and options.keep_previous ~= true then
        removeKey(route.activeId)
    end

    local meta = { routeId = normalizeId(routeId), index = index }

    if type(options.meta) == "table" then
        for name, value in pairs(options.meta) do meta[name] = value end
    end

    local payload = {
        id              = id,
        coords          = coords,
        style           = options.style,
        icon            = options.icon,
        label           = options.label,
        render_distance = options.render_distance,
        ground_line     = options.ground_line,
        visible         = options.visible ~= false,
        meta            = meta,
    }

    local ok

    if waypoints[key] then
        ok = update(owner, id, payload)
    else
        ok = create(owner, payload)
    end

    if not ok then return false end

    route.ids[key]    = true
    route.activeId    = key
    route.activeIndex = index

    return true
end

local function clearRoute(owner, routeId)
    local route, key = getRoute(owner, routeId)

    for id in pairs(route.ids) do removeKey(id) end

    routes[key] = nil

    return true
end

local function clearOwner(owner)
    for key, waypoint in pairs(waypoints) do
        if waypoint.owner == owner then removeKey(key) end
    end

    local prefix = ("%s:"):format(owner)

    for key in pairs(routes) do
        if key:sub(1, #prefix) == prefix then routes[key] = nil end
    end
end

local function invoker()
    return GetInvokingResource() or RESOURCE
end

exports("ggWaypointCreate", function(data)
    return create(invoker(), data)
end)

exports("ggWaypointUpdate", function(id, data)
    return update(invoker(), id, data)
end)

exports("ggWaypointRemove", function(id)
    return removeKey(keyOf(invoker(), normalizeId(id) or ""))
end)

exports("ggWaypointExists", function(id)
    return waypoints[keyOf(invoker(), normalizeId(id) or "")] ~= nil
end)

exports("ggWaypointShow", function(id)
    return update(invoker(), id, { visible = true })
end)

exports("ggWaypointHide", function(id)
    return update(invoker(), id, { visible = false })
end)

exports("ggWaypointSetRoutePoint", function(routeId, index, coords, options)
    return setRoutePoint(invoker(), routeId, index, coords, options)
end)

exports("ggWaypointClearRoute", function(routeId)
    return clearRoute(invoker(), routeId)
end)

exports("ggWaypointActiveRoutePoint", function(routeId)
    local route    = getRoute(invoker(), routeId)
    local waypoint = route.activeId and waypoints[route.activeId]

    if not waypoint then return nil end

    return {
        id     = waypoint.id,
        index  = route.activeIndex,
        coords = waypoint.coords,
        label  = waypoint.label,
    }
end)

exports("ggWaypointClear", function()
    clearOwner(invoker())

    return true
end)

local TEST_ID = "studio_test"
local TEST_SECONDS = 10

local testRun = 0

RegisterNUICallback("waypoint_try", function(data, cb)
    cb({ ok = true })

    local style = data and data.style

    if type(style) ~= "string" or not STYLES[style] then return end

    local seconds = tonumber(data and data.seconds) or TEST_SECONDS

    create(RESOURCE, {
        id              = TEST_ID,
        coords          = GetEntityCoords(PlayerPedId()),
        style           = style,
        label           = data.label,
        render_distance = data.render_distance,
        ground_line     = data.ground_line,
    })

    testRun = testRun + 1

    local mine = testRun

    SetTimeout(math.floor(seconds * 1000), function()
        if testRun ~= mine then return end

        removeKey(keyOf(RESOURCE, TEST_ID))
    end)
end)

CreateThread(function()
    Wait(2500)
    refreshStyleDefaults()
end)

RegisterNetEvent("gg_lib:generic:sync", function()
    refreshStyleDefaults()
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource == RESOURCE then
        for key in pairs(waypoints) do removeKey(key) end

        routes = {}
        return
    end

    clearOwner(resource)
end)

local DEBUG_ID = "debug"

local function tell(message)
    GGPopup.flash(message)

    print(("[gg_lib] %s"):format(message))
end

local function mapMarker()
    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then return nil end

    local at = GetBlipInfoIdCoord(blip)
    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, 1000.0, false)

    return vec3(at.x, at.y, found and groundZ or at.z)
end

local function debugWaypoint(_, args)
    local key = keyOf(RESOURCE, DEBUG_ID)

    if waypoints[key] then
        removeKey(key)
        tell("Debug waypoint removed")
        return
    end

    local first = args and args[1] and tostring(args[1]):lower() or nil
    local coords, from

    if first == "map" then
        coords = mapMarker()

        if not coords then
            tell("Set a marker on the map first, then run this again")
            return
        end

        from = "your map marker"
    else
        coords = GetEntityCoords(PlayerPedId())
        from = "your feet"
    end

    local label = "CHECKPOINT"

    if first and first ~= "map" then
        local joined = table.concat(args, " "):upper()

        if joined ~= "" then label = joined end
    end

    if not create(RESOURCE, { id = DEBUG_ID, coords = coords, label = label }) then
        tell("Could not place the debug waypoint")
        return
    end

    tell(("Debug waypoint placed at %s -- run the command again to remove it"):format(from))
    print(("[gg_lib] waypoint at %.2f, %.2f, %.2f"):format(coords.x, coords.y, coords.z))
end

RegisterCommand("ggwaypoint", debugWaypoint, false)
RegisterCommand("waypoint", debugWaypoint, false)

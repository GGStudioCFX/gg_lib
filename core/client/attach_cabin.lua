GG_ATTACH_CABIN = {}
local Cabin = GG_ATTACH_CABIN

local function clamp(n, low, high) return math.max(low, math.min(high, n)) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end

function Cabin.world(view, point)
    local out = {}
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        out[axis] = view.origin[axis] + view.right[axis] * point.x
            + view.forward[axis] * point.y + view.up[axis] * point.z
    end
    return out
end

function Cabin.localPoint(view, point)
    local delta = sub(point, view.origin)
    return { x = dot(delta, view.right), y = dot(delta, view.forward), z = dot(delta, view.up) }
end

function Cabin.preset(view, name)
    local point = view.views[name]
    if not point then return false end
    view.preset = name
    for _, axis in ipairs({ 'x', 'y', 'z' }) do view[axis] = point[axis] end
    local delta = sub(view.target, point)
    view.yaw = math.deg(math.atan(delta.x, delta.y))
    view.pitch = math.deg(math.atan(delta.z, math.sqrt(delta.x * delta.x + delta.y * delta.y)))
    view.fov = 65.0
    return true
end

function Cabin.create(vehicle)
    local low, high = GetModelDimensions(GetEntityModel(vehicle))
    local origin = GetEntityCoords(vehicle)
    local view = {
        origin = { x = origin.x, y = origin.y, z = origin.z },
        rotation = GetEntityRotation(vehicle, 2),
        right = sub(GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0), origin),
        forward = sub(GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0), origin),
        up = sub(GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, 1.0), origin),
    }
    local function seat(name, side)
        local bone = name and GetEntityBoneIndexByName(vehicle, name) or -1
        if bone ~= -1 then
            local point = Cabin.localPoint(view, GetWorldPositionOfEntityBone(vehicle, bone))
            if point.x > low.x and point.x < high.x and point.y > low.y and point.y < high.y
                and point.z > low.z and point.z < high.z then return point end
        end
        return { x = (low.x + high.x) * 0.5 + (high.x - low.x) * side * 0.22,
            y = low.y + (high.y - low.y) * 0.50, z = low.z + (high.z - low.z) * 0.38 }
    end
    local driver, passenger = seat('seat_dside_f', -1), seat('seat_pside_f', 1)
    if math.abs(driver.x - passenger.x) < 0.25 then driver, passenger = seat(nil, -1), seat(nil, 1) end
    local center = { x = (driver.x + passenger.x) * 0.5,
        y = (driver.y + passenger.y) * 0.5, z = (driver.z + passenger.z) * 0.5 }
    -- A conservative front-cabin envelope, inset from the model's exterior.
    local bounds = {
        min = { x = math.max(low.x + 0.18, math.min(driver.x, passenger.x) - 0.24),
            y = math.max(low.y + 0.25, center.y - 0.40), z = math.max(low.z + 0.20, center.z - 0.12) },
        max = { x = math.min(high.x - 0.18, math.max(driver.x, passenger.x) + 0.24),
            y = math.min(high.y - 0.45, center.y + 0.78), z = math.min(high.z - 0.12, center.z + 0.72) },
    }
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if bounds.max[axis] - bounds.min[axis] < 0.25 then return nil, 'vehicle cabin is too small for placement' end
    end
    view.bounds = bounds
    view.cameraBounds = { min = {}, max = {} }
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        view.cameraBounds.min[axis] = bounds.min[axis] + 0.06
        view.cameraBounds.max[axis] = bounds.max[axis] - 0.06
    end
    local function cameraPoint(x)
        return { x = clamp(x, view.cameraBounds.min.x, view.cameraBounds.max.x),
            y = clamp(center.y - 0.18, view.cameraBounds.min.y, view.cameraBounds.max.y),
            z = clamp(center.z + 0.50, view.cameraBounds.min.z, view.cameraBounds.max.z) }
    end
    view.target = { x = center.x, y = math.min(bounds.max.y, center.y + 0.55),
        z = clamp(center.z + 0.30, bounds.min.z, bounds.max.z) }
    view.views = { center = cameraPoint(center.x), driver = cameraPoint(driver.x * 0.65 + center.x * 0.35),
        passenger = cameraPoint(passenger.x * 0.65 + center.x * 0.35) }
    Cabin.preset(view, 'center')
    return view
end

function Cabin.look(view, dx, dy, nativeInput)
    -- Cursor drags are fractions of viewport height; native mouse axes use a separate gain.
    local yawGain, pitchGain = nativeInput and 8.0 or 60.0, nativeInput and 6.0 or 45.0
    view.yaw = clamp(view.yaw + dx * yawGain, -170.0, 170.0)
    view.pitch = clamp(view.pitch - dy * pitchGain, -65.0, 65.0)
end

function Cabin.move(view, forward, right, up, seconds, fast)
    local step = clamp(seconds, 0.0, 0.05) * (fast and 0.65 or 0.32)
    local yaw = math.rad(view.yaw)
    view.x = clamp(view.x + (right * math.cos(yaw) + forward * math.sin(yaw)) * step,
        view.cameraBounds.min.x, view.cameraBounds.max.x)
    view.y = clamp(view.y + (forward * math.cos(yaw) - right * math.sin(yaw)) * step,
        view.cameraBounds.min.y, view.cameraBounds.max.y)
    view.z = clamp(view.z + up * step, view.cameraBounds.min.z, view.cameraBounds.max.z)
end

function Cabin.camera(view)
    local yaw, pitch = math.rad(view.yaw), math.rad(view.pitch)
    return Cabin.world(view, view), Cabin.world(view, {
        x = view.x + math.sin(yaw) * math.cos(pitch),
        y = view.y + math.cos(yaw) * math.cos(pitch), z = view.z + math.sin(pitch),
    })
end

function Cabin.stationary(view, vehicle)
    local delta = sub(GetEntityCoords(vehicle), view.origin)
    if dot(delta, delta) > 0.04 then return false end
    local rotation = GetEntityRotation(vehicle, 2)
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if math.abs((rotation[axis] - view.rotation[axis] + 180.0) % 360.0 - 180.0) > 2.0 then return false end
    end
    return true
end

function Cabin.fit(view, at, right, forward, up, low, high)
    local localAt = Cabin.localPoint(view, at)
    local minimum, maximum = {}, {}
    for _, axis in ipairs({ 'x', 'y', 'z' }) do minimum[axis], maximum[axis] = math.huge, -math.huge end
    for _, x in ipairs({ low.x, high.x }) do
        for _, y in ipairs({ low.y, high.y }) do
            for _, z in ipairs({ low.z, high.z }) do
                local corner = { x = right.x * x + forward.x * y + up.x * z,
                    y = right.y * x + forward.y * y + up.y * z, z = right.z * x + forward.z * y + up.z * z }
                local offset = { x = dot(corner, view.right), y = dot(corner, view.forward), z = dot(corner, view.up) }
                for _, axis in ipairs({ 'x', 'y', 'z' }) do
                    minimum[axis] = math.min(minimum[axis], offset[axis])
                    maximum[axis] = math.max(maximum[axis], offset[axis])
                end
            end
        end
    end
    local limited = false
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        local lowAt, highAt = view.bounds.min[axis] - minimum[axis], view.bounds.max[axis] - maximum[axis]
        if lowAt > highAt then return nil, true end
        local value = clamp(localAt[axis], lowAt, highAt)
        if math.abs(value - localAt[axis]) > 0.00001 then limited = true end
        localAt[axis] = value
    end
    return Cabin.world(view, localAt), limited
end

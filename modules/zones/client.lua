-- gg.zones: poly, box and sphere zones with onEnter, onExit and inside callbacks.
-- gg_lib's own code, no ox_lib. The calls match lib.zones, so moving a script
-- over is a rename:
--
--   local zone = gg.zones.poly({ points = { vec3(..), vec3(..), vec3(..) }, thickness = 4.0,
--       onEnter = function(self) end, onExit = function(self) end, inside = function(self) end })
--   gg.zones.box({ coords = vec3(..), size = vec3(4.0, 4.0, 4.0), rotation = 90.0, ... })
--   gg.zones.sphere({ coords = vec3(..), radius = 2.0, ... })
--
--   zone:contains(coords)  zone:remove()  zone:setDebug(on, colour)
--   zone.insideZone  zone.distance  zone.coords  zone.radius  zone.id  zone.__type
--
-- One thread checks all of this script's zones every 300 ms: a bounding circle
-- first, the exact shape only when the player is near. A per-frame tick runs
-- only while the player is in a zone with `inside`, or a zone draws debug. Both
-- threads stop when nothing needs them. A poly is as tall as its lowest corner
-- minus half the thickness up to its highest corner plus half, so corners at
-- different heights just work (old ox_lib crashed on those, ticket 0200).
-- Zones live in this script's Lua state only and go when the script stops.
-- The data table passed in is copied, never changed, so one config table can
-- build any number of zones.

gg.zones = gg.zones or {}

local RESOURCE = GetCurrentResourceName()

local SCAN_MS    = 300
local DRAW_RANGE = 150.0  -- debug draws a zone while the player is this close to its edge
local DRAW_SPAN  = 40.0   -- and never taller than this above and below the player
local COLOUR     = { r = 255, g = 42, b = 24, a = 100 }

local sqrt, abs, huge, floor = math.sqrt, math.abs, math.huge, math.floor
local cos, sin, rad, atan = math.cos, math.sin, math.rad, math.atan

local zones = {}   -- every live zone, in no set order
local slot  = {}   -- zone -> its index in zones
local lastId = 0

local entering, enterN = {}, 0
local exiting, exitN = {}, 0
local framed, framedN = {}, 0   -- zones the per-frame tick works on

local scanning, ticking = false, false
local px, py, pz = 0.0, 0.0, 0.0

-- MARK: Helpers

-- x, y, z of a vector2/3/4, a { x =, y =, z = } or a { x, y, z } table.
local function read(point)
    local kind = type(point)

    if kind == "vector3" or kind == "vector4" then return point.x, point.y, point.z end
    if kind == "vector2" then return point.x, point.y, nil end
    if kind ~= "table" then return nil end

    local x, y, z = point.x or point[1], point.y or point[2], point.z or point[3]

    return tonumber(x), tonumber(y), tonumber(z)
end

local function playerPosition()
    local coords = GetEntityCoords(PlayerPedId())

    return coords.x, coords.y, coords.z
end

local function warn(message, ...)
    print(("^3[gg.zones] %s: " .. message .. "^7"):format(RESOURCE, ...))
end

local function failed(err)
    return debug.traceback(tostring(err), 2)
end

local function fire(zone, name)
    local ok, err = xpcall(zone[name], failed, zone)

    if ok then return end

    -- `inside` runs every frame: one failure turns it off instead of filling the console.
    if name == "inside" then zone.inside = nil end

    print(("^1[gg.zones] %s: zone %s %s failed%s^7\n%s"):format(
        RESOURCE, zone.id, name, name == "inside" and " and was turned off" or "", err))
end

local function debugWanted()
    local debugApi = gg.debug

    return debugApi ~= nil and debugApi.on ~= nil and debugApi.on() == true
end

local function farthestFirst(a, b) return a.distance > b.distance end
local function nearestFirst(a, b) return a.distance < b.distance end

-- MARK: Zone

local Zone = {}

-- coords: vector3, a table, or nil for the player. updateDistance also sets zone.distance.
function Zone:contains(coords, updateDistance)
    local x, y, z

    if coords == nil then
        x, y, z = playerPosition()
    else
        x, y, z = read(coords)

        if not x or not y then return false end
    end

    z = z or self._cz

    if updateDistance then
        local dx, dy, dz = self._cx - x, self._cy - y, self._cz - z

        self.distance = sqrt(dx * dx + dy * dy + dz * dz)
    end

    return self:holds(x, y, z)
end

function Zone:remove()
    local index = slot[self]

    if not index then return end

    local count = #zones
    local last = zones[count]

    zones[index] = last
    slot[last] = index
    zones[count] = nil
    slot[self] = nil

    self.insideZone = false
end

function Zone:isActive()
    return slot[self] ~= nil
end

local function colourOf(colour, base)
    base = base or COLOUR

    if type(colour) ~= "table" then return base end

    return {
        r = floor(tonumber(colour.r or colour[1]) or base.r),
        g = floor(tonumber(colour.g or colour[2]) or base.g),
        b = floor(tonumber(colour.b or colour[3]) or base.b),
        a = floor(tonumber(colour.a or colour[4]) or base.a),
    }
end

local function show(zone, on, colour)
    zone.debug = on and true or nil

    if on or colour then zone.debugColour = colourOf(colour, zone.debugColour) end
end

-- Draws the zone every frame while on. gg_lib's debug setting draws every zone too.
function Zone:setDebug(on, colour)
    self._ownDebug = on == true

    show(self, self._ownDebug or debugWanted(), colour)
end

local function class(methods)
    local cls = {}

    for name, method in pairs(Zone) do cls[name] = method end
    for name, method in pairs(methods) do cls[name] = method end

    cls.__index = cls

    return cls
end

-- MARK: Shapes

-- The walls of a poly or box from minZ to maxZ, clipped near the player.
local function drawWalls(zone)
    local bottom, top = zone.minZ, zone.maxZ

    if bottom < pz - DRAW_SPAN then bottom = pz - DRAW_SPAN end
    if top > pz + DRAW_SPAN then top = pz + DRAW_SPAN end
    if bottom >= top then return end

    local colour = zone.debugColour or COLOUR
    local r, g, b, a = colour.r, colour.g, colour.b, colour.a
    local xs, ys, n = zone._xs, zone._ys, zone._n

    for i = 1, n do
        local j = i < n and i + 1 or 1
        local ax, ay, bx, by = xs[i], ys[i], xs[j], ys[j]

        DrawLine(ax, ay, bottom, ax, ay, top, r, g, b, 225)
        DrawLine(ax, ay, top, bx, by, top, r, g, b, 225)
        DrawLine(ax, ay, bottom, bx, by, bottom, r, g, b, 225)

        DrawPoly(ax, ay, top, ax, ay, bottom, bx, by, top, r, g, b, a)
        DrawPoly(bx, by, top, ax, ay, bottom, ax, ay, top, r, g, b, a)
        DrawPoly(ax, ay, bottom, bx, by, top, bx, by, bottom, r, g, b, a)
        DrawPoly(bx, by, bottom, bx, by, top, ax, ay, bottom, r, g, b, a)
    end
end

local Poly = class({
    -- Even-odd crossing test in 2D, then the height band.
    holds = function(self, x, y, z)
        if z < self.minZ or z > self.maxZ then return false end

        local xs, ys, n = self._xs, self._ys, self._n
        local inside = false
        local j = n

        for i = 1, n do
            local xi, yi, yj = xs[i], ys[i], ys[j]

            if (yi > y) ~= (yj > y) and x < (xs[j] - xi) * (y - yi) / (yj - yi) + xi then
                inside = not inside
            end

            j = i
        end

        return inside
    end,

    draw = drawWalls,
})

local Box = class({
    holds = function(self, x, y, z)
        if abs(z - self._cz) > self._hz then return false end

        local dx, dy = x - self._cx, y - self._cy
        local along = dx * self._cos + dy * self._sin

        if along > self._hx or along < -self._hx then return false end

        local across = dy * self._cos - dx * self._sin

        return across <= self._hy and across >= -self._hy
    end,

    draw = drawWalls,
})

local Sphere = class({
    holds = function(self, x, y, z)
        local dx, dy, dz = x - self._cx, y - self._cy, z - self._cz

        return dx * dx + dy * dy + dz * dz < self._r2
    end,

    draw = function(self)
        local colour = self.debugColour or COLOUR
        local radius = self.radius

        DrawMarker(28, self._cx, self._cy, self._cz, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius, radius, radius,
            colour.r, colour.g, colour.b, colour.a, false, false, 0, false, false, false, false)
    end,
})

-- MARK: Loop

local function tick()
    if ticking then return end

    ticking = true

    CreateThread(function()
        while framedN > 0 do
            for i = 1, framedN do
                local zone = framed[i]

                if zone and slot[zone] then
                    if zone.debug then zone:draw() end
                    if zone.insideZone and zone.inside then fire(zone, "inside") end
                end
            end

            Wait(0)
        end

        ticking = false
    end)
end

local function scan()
    px, py, pz = playerPosition()

    local count, framing = #zones, 0

    for i = 1, count do
        local zone = zones[i]
        local dx, dy, dz = zone._cx - px, zone._cy - py, zone._cz - pz
        local flat = dx * dx + dy * dy
        local hit = flat <= zone._reach2 and zone:holds(px, py, pz)

        zone.distance = sqrt(flat + dz * dz)

        if hit ~= zone.insideZone then
            zone.insideZone = hit

            if hit then
                if zone.onEnter then
                    enterN = enterN + 1
                    entering[enterN] = zone
                end
            elseif zone.onExit then
                exitN = exitN + 1
                exiting[exitN] = zone
            end
        end

        if (hit and zone.inside) or (zone.debug and flat <= zone._drawReach2) then
            framing = framing + 1
            framed[framing] = zone
        end
    end

    for i = framing + 1, framedN do framed[i] = nil end

    framedN = framing

    -- Exits before enters, so walking from one zone into the next leaves first.
    if exitN > 0 then
        local n = exitN

        exitN = 0

        if n > 1 then table.sort(exiting, farthestFirst) end

        for i = 1, n do
            local zone = exiting[i]

            exiting[i] = nil

            if slot[zone] then fire(zone, "onExit") end
        end
    end

    if enterN > 0 then
        local n = enterN

        enterN = 0

        if n > 1 then table.sort(entering, nearestFirst) end

        for i = 1, n do
            local zone = entering[i]

            entering[i] = nil

            -- Skipped if a callback before it removed the zone.
            if slot[zone] and zone.insideZone then fire(zone, "onEnter") end
        end
    end

    if framedN > 0 then tick() end
end

local function wake()
    if scanning then return end

    scanning = true

    CreateThread(function()
        while #zones > 0 do
            scan()
            Wait(SCAN_MS)
        end

        for i = 1, framedN do framed[i] = nil end

        framedN = 0
        scanning = false
    end)
end

-- MARK: Building

local function build(cls, kind, data)
    local zone = setmetatable({}, cls)

    for key, value in pairs(data) do zone[key] = value end

    lastId = lastId + 1

    zone.id = lastId
    zone.__type = kind
    zone.insideZone = false
    zone.debug = nil

    return zone
end

local function add(zone, data)
    zone._reach2 = zone.radius * zone.radius
    zone._drawReach2 = (zone.radius + DRAW_RANGE) * (zone.radius + DRAW_RANGE)
    zone.coords = vector3(zone._cx, zone._cy, zone._cz)

    local x, y, z = playerPosition()
    local dx, dy, dz = zone._cx - x, zone._cy - y, zone._cz - z

    zone.distance = sqrt(dx * dx + dy * dy + dz * dz)

    zone:setDebug(data.debug == true, data.debugColour)

    zones[#zones + 1] = zone
    slot[zone] = #zones

    wake()

    return zone
end

-- data.points: 3+ corners. thickness (default 4) adds half above the highest corner
-- and half below the lowest. Corners without a z make a zone of any height.
-- data.minZ / data.maxZ set the band directly.
function gg.zones.poly(data)
    if type(data) ~= "table" or type(data.points) ~= "table" then
        warn("gg.zones.poly needs a points list")

        return nil
    end

    local xs, ys, polygon = {}, {}, {}
    local low, high, flat = huge, -huge, false
    local sumX, sumY = 0.0, 0.0

    for _, point in ipairs(data.points) do
        local x, y, z = read(point)

        if x and y then
            local n = #xs + 1

            xs[n], ys[n] = x + 0.0, y + 0.0
            sumX, sumY = sumX + x, sumY + y

            if z then
                if z < low then low = z end
                if z > high then high = z end
            else
                flat = true
            end
        end
    end

    local n = #xs

    if n < 3 then
        warn("gg.zones.poly needs at least 3 points, got %d", n)

        return nil
    end

    local zone = build(Poly, "poly", data)
    local thickness = tonumber(data.thickness) or 4.0
    local half = thickness / 2

    if flat then
        low, high = -huge, huge
    else
        low, high = low - half, high + half
    end

    zone.minZ = tonumber(data.minZ) or low
    zone.maxZ = tonumber(data.maxZ) or high
    zone.thickness = thickness
    zone._xs, zone._ys, zone._n = xs, ys, n
    zone._cx, zone._cy = sumX / n, sumY / n

    local mid = (zone.minZ + zone.maxZ) / 2

    -- A zone of any height still needs a real centre height for its distance.
    if mid ~= mid or mid == huge or mid == -huge then
        local _, _, z = read(data.points[1])

        mid = z or 0.0
    end

    zone._cz = mid

    local reach = 0.0

    for i = 1, n do
        local dx, dy = xs[i] - zone._cx, ys[i] - zone._cy
        local d = dx * dx + dy * dy

        if d > reach then reach = d end

        polygon[i] = vector3(xs[i], ys[i], mid)
    end

    zone.radius = sqrt(reach) + 0.01
    zone.polygon = polygon

    return add(zone, data)
end

-- Heading in degrees from a number, a vector3 rotation's z, or a quaternion table { x, y, z, w }.
local function headingOf(rotation)
    if rotation == nil then return 0.0 end

    local number = tonumber(rotation)

    if number then return number end

    local kind = type(rotation)

    if kind == "vector3" then return rotation.z end
    if kind ~= "table" then return 0.0 end

    if rotation.w and rotation.x then
        local qx, qy, qz, qw = rotation.x, rotation.y, rotation.z, rotation.w

        return math.deg(atan(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz)))
    end

    return tonumber(rotation.z or rotation[3]) or 0.0
end

-- data.coords: the centre. data.size: full width (x), length (y) and height (z),
-- default 4 each. data.rotation: heading in degrees.
function gg.zones.box(data)
    if type(data) ~= "table" then
        warn("gg.zones.box needs a data table")

        return nil
    end

    local cx, cy, cz = read(data.coords)

    if not cx or not cy then
        warn("gg.zones.box needs coords")

        return nil
    end

    local sx, sy, sz = 4.0, 4.0, 4.0

    if data.size ~= nil then
        local x, y, z = read(data.size)

        sx, sy, sz = x or sx, y or sy, z or sz
    end

    local zone = build(Box, "box", data)
    local heading = headingOf(data.rotation)
    local c, s = cos(rad(heading)), sin(rad(heading))
    local hx, hy, hz = sx / 2, sy / 2, sz / 2

    cx, cy, cz = cx + 0.0, cy + 0.0, (cz or 0.0) + 0.0

    zone._cx, zone._cy, zone._cz = cx, cy, cz
    zone._hx, zone._hy, zone._hz = hx, hy, hz
    zone._cos, zone._sin = c, s
    zone.size = vector3(sx, sy, sz)
    zone.width, zone.length, zone.thickness = sx, sy, sz
    zone.rotation = heading
    zone.minZ, zone.maxZ = cz - hz, cz + hz

    local xs, ys, polygon = {}, {}, {}
    local corners = { hx, hy, -hx, hy, -hx, -hy, hx, -hy }

    for i = 1, 4 do
        local lx, ly = corners[i * 2 - 1], corners[i * 2]

        xs[i] = cx + lx * c - ly * s
        ys[i] = cy + lx * s + ly * c
        polygon[i] = vector3(xs[i], ys[i], cz)
    end

    zone._xs, zone._ys, zone._n = xs, ys, 4
    zone.polygon = polygon
    zone.radius = sqrt(hx * hx + hy * hy) + 0.01

    return add(zone, data)
end

-- data.coords: the centre. data.radius: default 2.
function gg.zones.sphere(data)
    if type(data) ~= "table" then
        warn("gg.zones.sphere needs a data table")

        return nil
    end

    local cx, cy, cz = read(data.coords)

    if not cx or not cy then
        warn("gg.zones.sphere needs coords")

        return nil
    end

    local zone = build(Sphere, "sphere", data)
    local radius = (tonumber(data.radius) or 2.0) + 0.0

    zone._cx, zone._cy, zone._cz = cx + 0.0, cy + 0.0, (cz or 0.0) + 0.0
    zone._r2 = radius * radius
    zone.radius = radius

    return add(zone, data)
end

-- MARK: Lists

-- id -> zone, for every live zone of this script.
function gg.zones.getAllZones()
    local out = {}

    for i = 1, #zones do out[zones[i].id] = zones[i] end

    return out
end

-- id -> zone, for the zones the player is in now.
function gg.zones.getCurrentZones()
    local out = {}

    for i = 1, #zones do
        local zone = zones[i]

        if zone.insideZone then out[zone.id] = zone end
    end

    return out
end

function gg.zones.count()
    return #zones
end

-- Removes every zone of this script. No onExit runs.
function gg.zones.clear()
    for i = #zones, 1, -1 do zones[i]:remove() end
end

-- Shows or hides debug on every zone after gg_lib's debug setting changes.
function gg.zones.refresh()
    local on = debugWanted()

    for i = 1, #zones do
        local zone = zones[i]

        show(zone, zone._ownDebug or on)
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource == RESOURCE then gg.zones.clear() end
end)

if settings then
    if settings.onChange then settings.onChange(gg.zones.refresh) end
    if settings.generic and settings.generic.onChange then settings.generic.onChange(gg.zones.refresh) end
end

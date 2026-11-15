gg.closeup = gg.closeup or {}

--------------------------------------------------
-- MARK: Close-up maths
--------------------------------------------------

-- The maths a hands-on close-up stands on, with no natives in it: easing and springs that hold at any
-- frame rate, the camera's axes from its rotation and back, a look turned as a direction, and the
-- framing solver that puts a camera where a set of points fills a set share of the picture. The client
-- half (client.lua) builds the camera, cursor and session on these. This file also runs outside the
-- game, to check framing at every rotation.

local C = gg.closeup

C.API = 1

local function v(x, y, z) return vector3(x + 0.0, y + 0.0, z + 0.0) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b) return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function len(a) return math.sqrt(dot(a, a)) end

local function norm(a)
    local l = len(a)

    return l > 1e-6 and a * (1.0 / l) or a
end

C.v, C.dot, C.cross, C.len, C.norm = v, dot, cross, len, norm

--------------------------------------------------
-- MARK: Easing and springs
--------------------------------------------------

function C.clamp(n, lo, hi) return math.max(lo or 0.0, math.min(hi or 1.0, n)) end
function C.lerp(a, b, t) return a + (b - a) * t end

--- Smoothstep: starts and lands gently.
function C.smooth(t) t = C.clamp(t) return t * t * (3.0 - 2.0 * t) end

--- Fast out, soft landing (a hand reaching).
function C.out(t) t = C.clamp(t) return 1.0 - (1.0 - t) ^ 3 end

--- Soft start, fast finish (a hand letting go).
function C.into(t) t = C.clamp(t) return t * t * t end

--- Lands a little past 1 and settles back (a flap springing open, a part seating). `s` is how far
--- past (1.7 is about 10 %).
function C.back(t, s)
    t, s = C.clamp(t) - 1.0, s or 1.7

    return 1.0 + t * t * ((s + 1.0) * t + s)
end

--- Eases `x` toward `to` with time constant 1/`rate` seconds, the same at any frame rate. Works on
--- numbers and vector3s.
function C.toward(x, to, rate, dt)
    return x + (to - x) * (1.0 - math.exp(-rate * dt))
end

local STEP = 1.0 / 120.0

--- A damped spring at rest at `at` (a number or a vector3); pull it with `s.to`.
function C.spring(at)
    at = at or 0.0

    return { x = at, v = at * 0.0, to = at }
end

--- One frame of a spring: `k` pulls it to `s.to`, `c` damps it. Long frames are cut into short steps
--- so a stiff spring never blows up. Critically damped is c = 2 * sqrt(k).
function C.step(s, k, c, dt)
    local left = math.min(dt, 0.1)

    while left > 1e-6 do
        local h = math.min(left, STEP)

        s.v = s.v + ((s.to - s.x) * k - s.v * c) * h
        s.x = s.x + s.v * h
        left = left - h
    end

    return s.x
end

--- A sudden push, in the spring's units a second.
function C.kick(s, push) s.v = s.v + push end

--------------------------------------------------
-- MARK: Directions and rotations
--------------------------------------------------

-- Camera rotations are (pitch, roll, yaw) in degrees, rotation order 2, as the game's own. Yaw 0 looks
-- along +Y; a prop's front is its -Y, so a camera square on to a prop looks along the prop's +Y.

--- A rotation's facing, right and up (roll ignored).
function C.basis(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local forward = v(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    local right = v(math.cos(rz), math.sin(rz), 0.0)

    return forward, right, cross(right, forward)
end

--- The rotation that looks along `dir`.
function C.look(dir)
    local flat = math.sqrt(dir.x * dir.x + dir.y * dir.y)

    return v(math.deg(math.atan(dir.z, flat)), 0.0, math.deg(math.atan(-dir.x, dir.y)))
end

--- Blends two directions by `w` and renormalises, so a turning look sweeps across instead of cutting
--- through the camera. Opposite directions turn about `up` (world up by default).
function C.nlerp(a, b, w, up)
    local d = a + (b - a) * w

    if len(d) < 1e-3 then
        local side = norm(cross(a, up or v(0.0, 0.0, 1.0)))

        if len(side) < 1e-3 then side = v(1.0, 0.0, 0.0) end

        d = a * math.cos(w * math.pi) + side * math.sin(w * math.pi)
    end

    return norm(d)
end

--- A point on the quadratic curve from `a` to `b` pulled toward `c`.
function C.bezier(a, c, b, u)
    local w = 1.0 - u

    return a * (w * w) + c * (2.0 * w * u) + b * (u * u)
end

--- Turns the wrap out of a heading difference: -180 to 180.
function C.wrap(deg)
    return (deg + 180.0) % 360.0 - 180.0
end

--------------------------------------------------
-- MARK: An entity's frame
--------------------------------------------------

-- A frame is { right, forward, up, origin } in the world (client.lua's frame(entity) reads one off an
-- entity). Points and directions go in and out of it here.

function C.toWorld(f, p) return f.origin + f.right * p.x + f.forward * p.y + f.up * p.z end
function C.dirToWorld(f, d) return f.right * d.x + f.forward * d.y + f.up * d.z end

function C.toLocal(f, p)
    local r = p - f.origin

    return v(dot(r, f.right), dot(r, f.forward), dot(r, f.up))
end

function C.dirToLocal(f, d) return v(dot(d, f.right), dot(d, f.forward), dot(d, f.up)) end

--- A frame from a heading (degrees) at a point, upright.
function C.frameOf(origin, heading)
    local h = math.rad(heading or 0.0)
    local forward = v(-math.sin(h), math.cos(h), 0.0)

    return { right = v(math.cos(h), math.sin(h), 0.0), forward = forward, up = v(0.0, 0.0, 1.0), origin = origin }
end

--- The eight corners of a box (low, high in the frame), in the world.
function C.corners(f, low, high)
    local out = {}

    for i = 0, 7 do
        local p = v(i % 2 == 0 and low.x or high.x, math.floor(i / 2) % 2 == 0 and low.y or high.y, i >= 4 and high.z or low.z)

        out[#out + 1] = C.toWorld(f, p)
    end

    return out
end

--------------------------------------------------
-- MARK: Framing
--------------------------------------------------

-- The camera's field of view is vertical, in degrees; the picture is `aspect` (width over height) wide.
-- A shot frames a set of world points (a part's box corners, every pose a moving part passes) from a
-- direction: fit() finds the distance, and the field of view when none is given, that puts them all
-- inside `fill` of the picture with nothing closer to the lens than `near`.

C.FRAMING = {
    fill = 0.72,     -- share of the picture the points may span (the rest is margin)
    near = 0.06,     -- nearest any framed point may come to the lens, metres
    fov = { 24.0, 55.0 }, -- the field of view an automatic shot picks from
    wide = 75.0,     -- widest it may go when the room will not let the camera back far enough
    distance = { 0.28, 4.5 },
    reach = 3.2,     -- preferred distance, in the points' radii (a narrower lens on small things)
}

local function spread(points, aim, dir)
    local right = norm(cross(dir, v(0.0, 0.0, 1.0)))

    if len(right) < 1e-3 then right = v(1.0, 0.0, 0.0) end

    local up = cross(right, dir)
    local out = {}

    for i, p in ipairs(points) do
        local r = p - aim

        out[i] = { x = dot(r, right), y = dot(r, up), z = dot(r, dir) }
    end

    return out, right, up
end

--- The distance from `aim` back along `dir` that frames every point at this field of view.
function C.distanceFor(points, aim, dir, fov, aspect, fill, near)
    local ty = math.tan(math.rad(fov) * 0.5) * (fill or C.FRAMING.fill)
    local tx = ty * (aspect or 16.0 / 9.0)
    local d = 0.0

    for _, p in ipairs((spread(points, aim, dir))) do
        d = math.max(d, math.abs(p.x) / tx - p.z, math.abs(p.y) / ty - p.z, (near or C.FRAMING.near) - p.z)
    end

    return d
end

--- The field of view that frames every point from `distance` back along `dir`.
function C.fovFor(points, aim, dir, distance, aspect, fill)
    local need = 0.0
    local a = aspect or 16.0 / 9.0

    for _, p in ipairs((spread(points, aim, dir))) do
        local depth = math.max(distance + p.z, 1e-3)

        need = math.max(need, math.abs(p.y) / depth, math.abs(p.x) / (depth * a))
    end

    return math.deg(2.0 * math.atan(need / (fill or C.FRAMING.fill)))
end

--- Frames `points` looking along `dir` (from the camera toward the aim). opts: aim (the points' middle by
--- default), fov (fixed; else chosen), aspect, fill, near, distance = { min, max }, fovRange = { min, max }.
--- Gives back { eye, aim, dir, rot, fov, distance, fits }; fits is false when even the widest lens at the
--- farthest distance cannot hold them all.
function C.fit(points, dir, opts)
    opts = opts or {}

    local F = C.FRAMING
    local aspect, fill, near = opts.aspect or 16.0 / 9.0, opts.fill or F.fill, opts.near or F.near
    local dmin, dmax = (opts.distance or F.distance)[1], (opts.distance or F.distance)[2]
    local fmin, fmax = (opts.fovRange or F.fov)[1], (opts.fovRange or F.fov)[2]
    local aim = opts.aim

    dir = norm(dir)

    if not aim then
        local lo, hi = v(math.huge, math.huge, math.huge), v(-math.huge, -math.huge, -math.huge)

        for _, p in ipairs(points) do
            lo = v(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z))
            hi = v(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z))
        end

        aim = (lo + hi) * 0.5
    end

    local fov = opts.fov

    if not fov then
        local radius = 0.0

        for _, p in ipairs(points) do radius = math.max(radius, len(p - aim)) end

        local prefer = C.clamp(radius * (opts.reach or F.reach), dmin, dmax)

        fov = C.clamp(C.fovFor(points, aim, dir, prefer, aspect, fill), fmin, fmax)
    end

    local distance = C.distanceFor(points, aim, dir, fov, aspect, fill, near)
    local fits = true

    if distance < dmin then
        distance = dmin
    elseif distance > dmax then
        distance = dmax
        fov = C.fovFor(points, aim, dir, distance, aspect, fill)

        if fov > (opts.wide or F.wide) then fov, fits = opts.wide or F.wide, false end
    end

    return { eye = aim - dir * distance, aim = aim, dir = dir, rot = C.look(dir), fov = fov + 0.0, distance = distance, fits = fits }
end

--- The direction a camera looks along to see the front of frame `f` from `yaw` degrees round to the
--- viewer's right and `pitch` degrees above (0, 0 is square on to the -Y face).
function C.viewDir(f, yaw, pitch)
    local y, p = math.rad(yaw or 0.0), math.rad(pitch or 0.0)
    local out = v(math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p))

    return norm(C.dirToWorld(f, out)) * -1.0
end

--- Where a world point lands in a camera's picture: x, y across and down (0-1, the middle 0.5) and its
--- depth in front of the lens. False when it is behind.
function C.project(p, eye, rot, fov, aspect)
    local forward, right, up = C.basis(rot)
    local r = p - eye
    local depth = dot(r, forward)

    if depth <= 1e-4 then return false, 0.0, 0.0, depth end

    local ty = math.tan(math.rad(fov) * 0.5)
    local tx = ty * (aspect or 16.0 / 9.0)

    return true, 0.5 + dot(r, right) / (depth * tx) * 0.5, 0.5 - dot(r, up) / (depth * ty) * 0.5, depth
end

--- Checks a pose against the points it should frame: every point inside the picture (with `edge`
--- spare, a share of the picture) and nearer than none of them than `near`. Gives back ok and the first
--- reason it is not.
function C.frames(points, eye, rot, fov, aspect, edge, near)
    edge = edge or 0.0

    for i, p in ipairs(points) do
        local ahead, x, y, depth = C.project(p, eye, rot, fov, aspect)

        if not ahead then return false, ("point %d is behind the camera"):format(i) end
        if depth < (near or 0.02) then return false, ("point %d is %.3f m from the lens"):format(i, depth) end
        if x < edge or x > 1.0 - edge or y < edge or y > 1.0 - edge then
            return false, ("point %d is out of the picture (%.2f, %.2f)"):format(i, x, y)
        end
    end

    return true
end

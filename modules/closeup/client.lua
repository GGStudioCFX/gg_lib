gg.closeup = gg.closeup or {}

--------------------------------------------------
-- MARK: Hands-on close-ups
--------------------------------------------------

-- One close-up at a time on a prop the player works with their hands: a light switch, a keypad, an
-- ATM, a press, a safe. gg.closeup.run(opts, fn) walks the player to the prop, glides the camera in
-- from exactly where the game's was, gives fn the cursor, picking, feedback and gestures, and puts
-- everything back the same way however it ends: done, cancelled, interrupted, errored or the
-- resource stopping. The maths is in shared.lua, which also runs outside the game.
--
-- The rules this follows:
--   * the game's own cursor over the prop, nothing drawn on the screen; an outline on the part
--     under it, never on a ped
--   * the camera never cuts: in from a still copy of the game's view, out to the live gameplay
--     camera; every move is a glide of its own (no SetCamActiveWithInterp chains)
--   * the cursor is only ever placed when the close-up opens
--   * cancel is a release of Esc or Backspace (200, 202, 194), never 177 (that is right click too)
--   * whatever the session started, it stops: sounds, loops, clips, scenes, props, outlines

local C = gg.closeup
local v, dot, cross, len, norm = C.v, C.dot, C.cross, C.len, C.norm

--------------------------------------------------
-- MARK: Numbers at the native boundary
--------------------------------------------------

-- Lua 5.4 keeps integers and floats apart and FiveM passes them as they are: SetCamFov(cam, 50)
-- gives the game the bits of integer 50 (a field of view of 7e-44), and a float in an int slot is
-- read as garbage. Every number this file hands a native goes through one of these.

local function F(n) return (n or 0) + 0.0 end
local function I(n) return math.tointeger(n) or math.floor(n + 0.5) end

C.F, C.I = F, I

--------------------------------------------------
-- MARK: Flags
--------------------------------------------------

C.ANIM = {
    LOOP = 1, HOLD = 2, REPOSITION = 4, NOT_INTERRUPTABLE = 8, UPPERBODY = 16, SECONDARY = 32,
    ABORT_ON_MOVE = 128, ADDITIVE = 256, NO_COLLISION = 512, HIDE_WEAPON = 1048576,
    WORK = 49, -- loop + upper body + secondary: hands busy, legs free
}

C.SCENE = {
    USE_PHYSICS = 1, TAG_SYNC_OUT = 2, DONT_INTERRUPT = 4, ON_ABORT_STOP_SCENE = 8,
    ABORT_ON_WEAPON_DAMAGE = 16, BLOCK_MOVER_UPDATE = 32, LOOP_WITHIN_SCENE = 64,
    PRESERVE_VELOCITY = 128, EXPAND_CAPSULE = 256, RAGDOLL_ON_COLLISION = 512, HIDE_WEAPON = 1024,
    ABORT_ON_DEATH = 2048,
    PED = 1 | 1024 | 2048, -- the usual for the player in a scene: physics on, weapon hidden, ends on death
}

-- Close keys (released, not pressed, so the same press never also reaches the menu behind) and the
-- shape-test flags a camera checks its view with (world and objects).
C.CANCEL = { 200, 202, 194 }

local LOS = 1 | 16
local UNARMED = joaat("WEAPON_UNARMED")
local TASK_HEADING, TASK_WALK = joaat("SCRIPT_TASK_ACHIEVE_HEADING"), joaat("SCRIPT_TASK_GO_STRAIGHT_TO_COORD")
local SPRITES = { press = 5, grab = 3, hold = 4 }

--------------------------------------------------
-- MARK: Loading
--------------------------------------------------

local LOADERS = {
    model = function(name)
        local hash = type(name) == "number" and name or joaat(name)

        if not IsModelInCdimage(hash) then return nil end

        RequestModel(hash)

        return function() return HasModelLoaded(hash) end
    end,
    dict = function(name)
        if not DoesAnimDictExist(name) then return nil end

        RequestAnimDict(name)

        return function() return HasAnimDictLoaded(name) end
    end,
    fx = function(name)
        RequestNamedPtfxAsset(name)

        return function() return HasNamedPtfxAssetLoaded(name) end
    end,
    bank = function(name)
        return function() return RequestScriptAudioBank(name, false, -1) end
    end,
}

--- Loads a model, an anim dict ("dict"), a particle asset ("fx") or a script audio bank ("bank"),
--- waiting up to `ms` (2000). False when it does not exist or never loaded.
function C.load(kind, name, ms)
    local start = LOADERS[kind] and LOADERS[kind](name)

    if not start then return false end

    local deadline = GetGameTimer() + (ms or 2000)

    while not start() do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

--------------------------------------------------
-- MARK: Natives with a catch
--------------------------------------------------

-- FiveM's Lua wrapper for FindAnimEventPhase reads both phases back as integers, so a phase of 0.5
-- comes back as 1056964608. Asking for floats outright gives the real ones; an integer that still
-- gets through is turned back into the float whose bits it is.
local function asFloat(n)
    if math.type(n) ~= "integer" then return n end
    if n < 0 then n = n + 4294967296 end

    return (string.unpack("<f", string.pack("<I4", n)))
end

C.asFloat = asFloat

--- Where a clip's event starts and ends, 0-1 of its length: found, from, to.
function C.eventPhase(dict, clip, event)
    local found, from, to = Citizen.InvokeNative(0x07F1BE2BCCAA27A7, dict, clip, event,
        Citizen.PointerValueFloat(), Citizen.PointerValueFloat(), Citizen.ReturnResultAnyway())

    if not found then return false end

    return true, asFloat(from), asFloat(to)
end

local outlined = nil

--- Outlines one entity (nil clears it). Never a ped: an outline on a ped crashes the game (FiveM
--- issue 1425), so a ped is refused.
function C.outline(entity, colour)
    if entity == outlined then return true end

    if outlined and DoesEntityExist(outlined) then SetEntityDrawOutline(outlined, false) end

    outlined = nil

    if not entity or not DoesEntityExist(entity) then return true end
    if IsEntityAPed(entity) then return false end

    local c = colour or { 255, 255, 255, 90 }

    SetEntityDrawOutlineColor(I(c[1]), I(c[2]), I(c[3]), I(c[4] or 90))
    SetEntityDrawOutline(entity, true)
    outlined = entity

    return true
end

--------------------------------------------------
-- MARK: Frames and boxes
--------------------------------------------------

--- An entity's frame in the world: { right, forward, up, origin }.
function C.frame(entity)
    local o = GetEntityCoords(entity)

    return {
        right = GetOffsetFromEntityInWorldCoords(entity, 1.0, 0.0, 0.0) - o,
        forward = GetOffsetFromEntityInWorldCoords(entity, 0.0, 1.0, 0.0) - o,
        up = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, 1.0) - o,
        origin = o,
    }
end

local sizes = {}

--- A model's box, low and high, in its own frame (read once per model).
function C.box(model)
    if type(model) == "string" then model = joaat(model) end

    local size = sizes[model]

    if not size then
        local low, high = GetModelDimensions(model)

        size = { low = low, high = high }
        sizes[model] = size
    end

    return size.low, size.high
end

--- The world points a shot frames. `what` is any mix of: { low, high } boxes in frame `f`, vector3
--- points in `f`, and entities (their whole model box, in their own frame).
function C.points(f, what)
    local out = {}

    for _, item in ipairs(what) do
        if type(item) == "number" then
            if DoesEntityExist(item) then
                local low, high = C.box(GetEntityModel(item))

                for _, p in ipairs(C.corners(C.frame(item), low, high)) do out[#out + 1] = p end
            end
        elseif type(item) == "table" and item[1] and item[2] then
            for _, p in ipairs(C.corners(f, item[1], item[2])) do out[#out + 1] = p end
        else
            out[#out + 1] = C.toWorld(f, item)
        end
    end

    return out
end

--------------------------------------------------
-- MARK: Rays and picking
--------------------------------------------------

-- A pose is { eye, dir, rot, fov }: what the close-up camera shows this frame. Rays and screen
-- points come off the pose the camera was last set to, never a target it is still gliding toward.

local function aspect() return GetAspectRatio(false) end

--- The ray from a pose through a point on the screen (0-1 across and down).
function C.ray(pose, x, y)
    local forward, right, up = C.basis(pose.rot)
    local ty = math.tan(math.rad(pose.fov) * 0.5)
    local tx = ty * aspect()

    return pose.eye, norm(forward + right * ((x - 0.5) * 2.0 * tx) + up * ((0.5 - y) * 2.0 * ty))
end

--- Where a world point lands on the screen from a pose; nil when behind it.
function C.screen(pose, p)
    local ahead, x, y = C.project(p, pose.eye, pose.rot, pose.fov, aspect())

    if ahead then return x, y end
end

--- Where a ray meets a plane (nil when it runs along it or away from it).
function C.onPlane(origin, dir, at, normal)
    local d = dot(dir, normal)

    if math.abs(d) < 1e-5 then return nil end

    local t = dot(at - origin, normal) / d

    if t < 0 then return nil end

    return origin + dir * t
end

local FACES = { xlow = "left", xhigh = "right", ylow = "front", yhigh = "back", zlow = "bottom", zhigh = "top" }

--- Where a ray meets a box (low, high in frame `f`): the point, which face (front is -Y) and the point
--- in the frame.
function C.hitBox(f, origin, dir, low, high)
    local rel = origin - f.origin
    local lo = { x = dot(rel, f.right), y = dot(rel, f.forward), z = dot(rel, f.up) }
    local ld = { x = dot(dir, f.right), y = dot(dir, f.forward), z = dot(dir, f.up) }
    local tmin, tmax, face = -math.huge, math.huge, nil

    for _, axis in ipairs({ "x", "y", "z" }) do
        if math.abs(ld[axis]) < 1e-6 then
            if lo[axis] < low[axis] or lo[axis] > high[axis] then return nil end
        else
            local t1, t2 = (low[axis] - lo[axis]) / ld[axis], (high[axis] - lo[axis]) / ld[axis]
            local side = "low"

            if t1 > t2 then t1, t2, side = t2, t1, "high" end
            if t1 > tmin then tmin, face = t1, axis .. side end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end

    if tmin < 0 or not face then return nil end

    return origin + dir * tmin, FACES[face], v(lo.x + ld.x * tmin, lo.y + ld.y * tmin, lo.z + ld.z * tmin)
end

--- What a ray hits of `parts`. A part is { entity, low, high, pad } (the entity's box, or low-high in
--- its frame, `pad` metres bigger all round so a small part is easy to hit), { frame, low, high, pad }
--- (a box with no prop of its own) or { at, radius } (a round spot). A part the ray meets itself wins,
--- nearest first; of those it only meets inside their pad, the one whose middle it passes closest to,
--- so two padded parts side by side never steal each other's cursor. Gives back the part and where.
function C.under(origin, dir, parts)
    local best, bestScore, bestAt, bestExact = nil, math.huge, nil, false

    for _, part in ipairs(parts) do
        local f, low, high = part.frame, part.low, part.high
        local hit, exact, score

        if part.entity then
            if DoesEntityExist(part.entity) then
                f = C.frame(part.entity)
                if not low then low, high = C.box(GetEntityModel(part.entity)) end
            else
                f = nil
            end
        end

        if f and low then
            local pad = part.pad or 0.0
            local grow = type(pad) == "number" and v(pad, pad, pad) or pad

            hit = C.hitBox(f, origin, dir, low - grow, high + grow)

            if hit then
                exact = len(grow) <= 0.0 or C.hitBox(f, origin, dir, low, high) ~= nil

                if exact then
                    score = len(hit - origin)
                else
                    local mid = C.toWorld(f, (low + high) * 0.5)

                    score = len(origin + dir * dot(mid - origin, dir) - mid)
                end
            end
        elseif part.at then
            local t = dot(part.at - origin, dir)

            if t > 0 and len(origin + dir * t - part.at) <= (part.radius or 0.02) then
                hit, exact, score = origin + dir * t, true, t
            end
        end

        if hit and ((exact and not bestExact) or (exact == bestExact and score < bestScore)) then
            best, bestScore, bestAt, bestExact = part, score, hit, exact
        end
    end

    return best, bestAt
end

--------------------------------------------------
-- MARK: Look and press
--------------------------------------------------

-- A prop worked with one press (a light switch, a bell, a lamp) takes no close-up: the player looks at
-- it and presses. What they look at is what the middle of their screen is on, from the camera they see
-- through, within reach of their hands and with nothing solid in between.

-- Why the player cannot work anything right now, or nil.
local function blocked(ped)
    if IsPedInAnyVehicle(ped, false) then return "vehicle" end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return "dead" end
    if IsPedRagdoll(ped) then return "ragdoll" end
    if IsPedFalling(ped) then return "falling" end
    if IsPedSwimming(ped) then return "swimming" end
    if IsPedClimbing(ped) then return "climbing" end
end

local sight = { part = nil, at = 0, clear = false }

--- Which of `parts` (see C.under) the middle of the screen is on, within `reach` (1.2 m) of the
--- player and in plain sight: the part and where, or nil. Cheap enough to call every frame near it.
function C.aimed(parts, reach)
    local ped = PlayerPedId()
    local eye = GetFinalRenderedCamCoord()
    local dir = C.basis(GetFinalRenderedCamRot(2))
    local part, at = C.under(eye, dir, parts)

    if not part or len(at - GetEntityCoords(ped)) > (reach or 1.2) then
        sight.part = nil

        return nil
    end

    -- One sight line a part every 150 ms: a wall or door between them and it blocks it.
    if part ~= sight.part or GetGameTimer() - sight.at > 150 then
        local to = at - dir * 0.03
        local probe = StartExpensiveSynchronousShapeTestLosProbe(F(eye.x), F(eye.y), F(eye.z), F(to.x), F(to.y), F(to.z), LOS, part.entity or ped, 7)
        local _, hit = GetShapeTestResult(probe)

        sight.part, sight.at, sight.clear = part, GetGameTimer(), not (hit == 1 or hit == true)
    end

    if not sight.clear then return nil end

    return part, at
end

local glances = {}

--- Props worked with one press, watched while the player is near: the part they look at is outlined
--- and a key uses it. The key is a key mapping, so players can rebind it in the game's settings.
--- opts:
---   use(part, at)  runs in a thread of its own when the key is pressed on a part (a part's own
---                  part.use wins, so one glance can work a switch, an ATM and a bench)
---   name          the mapping's command, unique in the resource ("gg_use")
---   label, key     what the key settings list it as ("Use"), and its default key ("E")
---   reach          how far the hands reach (1.2 m)
---   near           how near a part must be before it is looked for every frame (3 m)
---   colour         the outline ({ 255, 255, 255, 90 })
---   can(part)      false to skip a part right now
--- Gives back a glance: :add(part) and :remove(part) take parts as C.under does (and keep anything
--- else on them for use), :stop() ends it. It sleeps half a second at a time while nothing is near
--- and steps aside while a close-up or another GG tool is open.
function C.glance(opts)
    local g = { parts = {}, on = true, aimed = nil, busy = false, lit = nil }
    local name = opts.name or "gg_use"
    local reach, near = opts.reach or 1.2, opts.near or 3.0

    glances[#glances + 1] = g

    -- Only ever clears an outline it set: a close-up that opens over it owns the outline from then on.
    local function light(entity)
        if entity then
            C.outline(entity, opts.colour)
            g.lit = entity
        elseif g.lit then
            if outlined == g.lit then C.outline(nil) end

            g.lit = nil
        end
    end

    function g:add(part)
        self.parts[#self.parts + 1] = part

        return part
    end

    function g:remove(part)
        for i = #self.parts, 1, -1 do
            if self.parts[i] == part then table.remove(self.parts, i) end
        end

        if self.aimed == part then
            self.aimed = nil
            light(nil)
        end
    end

    function g:stop()
        self.on, self.aimed = false, nil
        light(nil)
    end

    RegisterCommand("+" .. name, function()
        local part, at = g.aimed, g.at
        local use = part and (part.use or opts.use)

        if not g.on or not use or g.busy then return end

        g.busy = true

        CreateThread(function()
            local ok, err = pcall(use, part, at)

            if not ok then print(("^1[gg.closeup] %s^7"):format(tostring(err))) end

            g.busy = false
        end)
    end, false)
    RegisterCommand("-" .. name, function() end, false)
    RegisterKeyMapping("+" .. name, opts.label or "Use", "keyboard", opts.key or "E")

    local function placeOf(part)
        if part.entity then return DoesEntityExist(part.entity) and GetEntityCoords(part.entity) or nil end
        if part.frame then return C.toWorld(part.frame, ((part.low or v(0.0, 0.0, 0.0)) + (part.high or v(0.0, 0.0, 0.0))) * 0.5) end

        return part.at
    end

    local function close()
        local ped = PlayerPedId()
        local here = GetEntityCoords(ped)
        local out = {}

        for _, part in ipairs(g.parts) do
            local at = placeOf(part)

            if at and len(at - here) <= near and (not opts.can or opts.can(part) ~= false) then out[#out + 1] = part end
        end

        return out
    end

    CreateThread(function()
        while g.on do
            local list = close()

            local ped = PlayerPedId()

            if #list == 0 then
                g.aimed = nil
                light(nil)
                Wait(500)
            elseif C.active() or LocalPlayer.state.ggTool or blocked(ped) or IsPauseMenuActive() then
                g.aimed = nil
                light(nil)
                Wait(250)
            else
                local part, at = C.aimed(list, reach)

                if part ~= g.aimed then
                    light(part and part.entity)
                    g.aimed = part
                end

                g.at = at
                Wait(0)
            end
        end
    end)

    return g
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for _, g in ipairs(glances) do g.on = false end

    C.outline(nil)
end)

--------------------------------------------------
-- MARK: Gestures
--------------------------------------------------

-- Small pieces a part's motion is made of. Each is a value with a spring under it, so the part moves
-- with weight and never snaps; the session poses the part's prop from it every frame.

local Press, Dial, Slide = {}, {}, {}
Press.__index, Dial.__index, Slide.__index = Press, Dial, Slide

--- A button with travel: :update(held, dt) gives how far in it is (0-1) and true the frame it
--- bottoms out (the click). A press goes all the way in once it starts, so a quick tap still clicks.
--- opts: k (stiffness).
function C.press(opts)
    opts = opts or {}

    return setmetatable({ s = C.spring(0.0), k = opts.k or 900.0, armed = true, was = false }, Press)
end

function Press:update(held, dt)
    if held and not self.was and self.armed then self.push = true end

    self.was = held
    self.s.to = (held or self.push) and 1.0 or 0.0

    local x = C.step(self.s, self.k, 2.0 * math.sqrt(self.k), dt)
    local clicked = false

    if self.armed and x >= 0.9 then
        self.armed, self.push, clicked = false, false, true
    elseif not self.armed and x <= 0.3 then
        self.armed = true
    end

    return C.clamp(x), clicked
end

--- A dial with detents: :turn(degrees) while held, :update(dt) settles it on the nearest detent and
--- gives the angle and how many detents it crossed this frame (a tick each). opts: detents (a turn),
--- min, max (degrees; none for endless).
function C.dial(opts)
    opts = opts or {}

    local step = 360.0 / (opts.detents or 12)

    return setmetatable({ s = C.spring(opts.at or 0.0), step = step, min = opts.min, max = opts.max, held = false, last = 0 }, Dial)
end

function Dial:turn(deg)
    local to = self.s.x + deg

    if self.min then to = math.max(self.min, to) end
    if self.max then to = math.min(self.max, to) end

    self.s.x, self.s.to, self.s.v, self.held = to, to, 0.0, true
end

function Dial:release() self.held = false end

function Dial:update(dt)
    if not self.held then
        self.s.to = math.floor(self.s.x / self.step + 0.5) * self.step
        C.step(self.s, 260.0, 26.0, dt)
    end

    local notch = math.floor(self.s.x / self.step + 0.5)
    local crossed = math.abs(notch - self.last)

    self.last = notch

    return self.s.x, crossed, notch
end

--- A part pushed or pulled along a line (a lever, a drawer, a card going into a slot): :follow(origin,
--- dir) moves it to where the ray passes the line closest, :update(dt) springs it there or, let go, to
--- the nearest of `stops` (0-1 along it). Gives back t (0-1) and the stop it came to rest on.
function C.slide(from, to, opts)
    opts = opts or {}

    return setmetatable({ from = from, to = to, s = C.spring(opts.at or 0.0), stops = opts.stops, held = false }, Slide)
end

function Slide:follow(origin, dir)
    local axis = self.to - self.from
    local l = len(axis)

    if l < 1e-5 then return end

    local a = axis * (1.0 / l)
    local w = origin - self.from
    local b = dot(a, dir)
    local denom = 1.0 - b * b

    if denom < 1e-5 then return end

    local t = (dot(w, a) - b * dot(w, dir)) / denom

    self.s.to, self.held = C.clamp(t / l), true
end

function Slide:release()
    self.held = false

    if not self.stops then return end

    local best, gap = self.s.x, math.huge

    for _, stop in ipairs(self.stops) do
        if math.abs(stop - self.s.x) < gap then best, gap = stop, math.abs(stop - self.s.x) end
    end

    self.s.to = best
end

function Slide:update(dt)
    local x = C.step(self.s, self.held and 700.0 or 320.0, self.held and 53.0 or 30.0, dt)
    local rest = nil

    if not self.held and math.abs(self.s.v) < 0.02 and math.abs(self.s.to - x) < 0.005 then rest = self.s.to end

    return C.clamp(x), rest
end

function Slide:at() return self.from + (self.to - self.from) * C.clamp(self.s.x) end

--- The socket nearest `at` within `radius` (0.08 m): a held part dropped near one seats in it.
function C.socket(at, sockets, radius)
    local best, gap = nil, radius or 0.08

    for i, socket in ipairs(sockets) do
        local d = len((socket.at or socket) - at)

        if d <= gap then best, gap = i, d end
    end

    return best, gap
end

--------------------------------------------------
-- MARK: The session
--------------------------------------------------

local S = {}
S.__index = S

local current = nil

local function now() return GetGameTimer() end

C.TIMING = {
    enter = 750,  -- the glide in
    reframe = 420, -- a move between shots
    leave = 600,  -- the glide out
    walk = 4000,  -- the longest the walk to the stand spot may take
}

-- Bones the close-up must not be inside, or see the player through.
local BONES = { 31086, 39317, 24818, 11816, 57005, 18905, 61163, 28252, 36864, 63931 }
local CLEAR = 0.6

-- Farther than this (metres) from the gameplay camera when it ends, the player was moved away at once
-- (a teleport): the close-up cuts out, as the game does, instead of swooping across the gap.
local CUT = 12.0

--- The session open right now in this resource, or nil.
function C.active() return current end

local function track(s, fn, late)
    local list = late and s.late or s.early

    list[#list + 1] = fn

    return fn
end

--- Runs `fn` after the session ends (before the camera leaves; with `late`, once it is out).
function S:defer(fn, late) return track(self, fn, late) end

function S:alive() return not self.over end

--- Ends the session from inside with `reason` (default "cancel").
function S:cancel(reason)
    if self.over then return end

    self.over, self.reason = true, reason or "cancel"
end

--- Waits `ms` unless the session ends first: false when it did.
function S:wait(ms)
    local till = now() + (ms or 0)

    repeat
        if self.over then return false end

        Wait(0)
    until now() >= till

    return not self.over
end

--- Lets the close keys end the session or not (a step that must not be left halfway).
function S:canCancel(on) self.cancellable = on ~= false end

--------------------------------------------------
-- MARK: The camera
--------------------------------------------------

-- The close-up's camera is set outright every frame from the session's own glide: a curve that
-- comes in along the shot's own line of sight, a look that turns early on the way in and late on
-- the way out, a field of view eased between. Nothing is left to the game's interpolation, so a
-- new shot can start mid-glide from exactly what is on the screen.

local function poseOf(eye, dir, fov)
    return { eye = eye, dir = dir, rot = C.look(dir), fov = fov }
end

local function gameplayPose()
    local rot = GetGameplayCamRot(2)
    local forward = C.basis(rot)

    return poseOf(GetGameplayCamCoord(), forward, GetGameplayCamFov())
end

local function startMove(s, to, ms, turn, ease)
    local from = s.lens
    local gap = len(to.eye - from.eye)
    local pull = C.clamp(gap * 0.25, 0.05, 0.6)

    s.move = {
        from = from, to = to, at = now(), ms = math.max(1, ms), turn = turn, ease = ease or C.smooth,
        ctrl = to.eye - to.dir * pull,
    }
end

local function setCam(s, pose)
    local rot = pose.rot

    if s.jolt then
        rot = rot + v(s.jolt.pitch.x, 0.0, s.jolt.yaw.x)
    end

    SetCamCoord(s.cam, F(pose.eye.x), F(pose.eye.y), F(pose.eye.z))
    SetCamRot(s.cam, F(rot.x), F(rot.y), F(rot.z), 2)
    SetCamFov(s.cam, F(pose.fov))
end

local function camTick(s, dt)
    local m = s.move

    if m then
        if m.live then
            local to = gameplayPose()

            -- The player was moved away mid-glide (a teleport): it cuts out instead of chasing them.
            if len(to.eye - m.to.eye) > CUT then
                s.move = nil

                return
            end

            m.to = to
        end

        local u = C.clamp((now() - m.at) / m.ms)
        local e = m.ease(u)
        local eye = C.bezier(m.from.eye, m.ctrl, m.to.eye, e)

        if m.live then eye = C.lerp(eye, m.to.eye, u * u) end

        s.lens = poseOf(eye, C.nlerp(m.from.dir, m.to.dir, m.turn(u)), C.lerp(m.from.fov, m.to.fov, e))

        if u >= 1.0 then
            s.lens, s.move = m.to, nil

            if s.queue[1] then
                local q = table.remove(s.queue, 1)

                startMove(s, q.pose, q.ms, q.turn)
            end
        end
    end

    local shown = s.lens

    if s.drift > 0 and not s.move then
        local t = now() * 0.001
        local a = s.drift

        shown = poseOf(s.lens.eye + v(math.sin(t * 0.7) * 0.004 * a, 0.0, math.sin(t * 0.9 + 1.3) * 0.003 * a), s.lens.dir, s.lens.fov)
        shown.rot = shown.rot + v(math.sin(t * 0.5) * 0.12 * a, 0.0, math.sin(t * 0.4 + 0.6) * 0.15 * a)
    end

    if s.jolt then
        C.step(s.jolt.pitch, 320.0, 14.0, dt)
        C.step(s.jolt.yaw, 320.0, 14.0, dt)

        if math.abs(s.jolt.pitch.x) + math.abs(s.jolt.yaw.x) + math.abs(s.jolt.pitch.v) + math.abs(s.jolt.yaw.v) < 1e-3 then s.jolt = nil end
    end

    s.shown = shown
    setCam(s, shown)

    if s.dof then SetUseHiDof() end
end

--- Pulls the eye in front of anything between it and the aim (a wall behind the player, a shelf).
local function clearEye(s, aim, eye)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(F(aim.x), F(aim.y), F(aim.z), F(eye.x), F(eye.y), F(eye.z), LOS, s.entity or 0, 7)
    local _, hit, at = GetShapeTestResult(probe)

    if hit == 1 or hit == true then
        local d = len(at - aim)

        return math.max(0.25, d - 0.12), true
    end

    return len(eye - aim), false
end

--- Works out a shot: where the camera goes to frame it. `spec`: box = { low, high } | boxes |
--- points (in the host's frame) | entities; yaw, pitch (degrees round from square on to the host's
--- front, and above it) or angles = { { yaw, pitch }, ... } to try in turn; fill, fov, near,
--- distance = { min, max }, aim (in the host's frame). Gives back the pose and whether it fits.
function S:frameShot(spec)
    local f = self.frame
    local what = spec.points or spec.boxes or (spec.box and { spec.box }) or spec.entities

    if not what then
        assert(self.entity, "a close-up with no entity needs shot.box, boxes, points or entities")

        local low, high = C.box(GetEntityModel(self.entity))

        what = { { low, high } }
    end

    local points = C.points(f, what)
    local angles = spec.angles or { { spec.yaw or 0.0, spec.pitch or 12.0 } }
    local aim = spec.aim and C.toWorld(f, spec.aim) or nil
    local best, bestRoom = nil, -math.huge

    for _, angle in ipairs(angles) do
        local dir = C.viewDir(f, angle[1], angle[2])
        local shot = C.fit(points, dir, {
            aim = aim, fov = spec.fov, aspect = aspect(), fill = spec.fill, near = spec.near, distance = spec.distance,
        })
        local room, blocked = clearEye(self, shot.aim, shot.eye)

        if blocked and room < shot.distance then
            shot.distance = room
            shot.eye = shot.aim - shot.dir * room
            shot.fov = C.fovFor(points, shot.aim, shot.dir, room, aspect(), spec.fill)

            if shot.fov > C.FRAMING.wide then shot.fov, shot.fits = C.FRAMING.wide, false end
        end

        local score = (shot.fits and 10.0 or 0.0) + (blocked and -1.0 or 0.0)

        if score > bestRoom then best, bestRoom = shot, score end
        if shot.fits and not blocked then break end
    end

    return poseOf(best.eye, best.dir, best.fov), best.fits, best
end

--- Moves the camera to a shot (see frameShot), gliding over spec.ms. spec.queue waits for the shot
--- before it to land first.
function S:shot(spec)
    local pose, fits, shot = self:frameShot(spec)

    self.aim = shot.aim
    local ms = spec.ms or C.TIMING.reframe
    local turn = function(u) return 1.0 - (1.0 - u) ^ 2 end

    if spec.queue and self.move then
        self.queue[#self.queue + 1] = { pose = pose, ms = ms, turn = turn }
    else
        self.queue = {}
        startMove(self, pose, ms, turn)
    end

    return pose, fits
end

--- Whether the camera is still gliding.
function S:moving() return self.move ~= nil end

--- Waits for the camera to land.
function S:settle()
    while self.move and not self.over do Wait(0) end

    return not self.over
end

--- A jolt to the view (a part seating, a lever hitting its stop): `strength` 0.1-0.25.
function S:kick(strength)
    local j = self.jolt or { pitch = C.spring(0.0), yaw = C.spring(0.0) }
    local push = (strength or 0.15) * 60.0

    C.kick(j.pitch, -push)
    C.kick(j.yaw, push * (math.random() - 0.5))
    self.jolt = j
end

--- The pose on the screen right now.
function S:view() return self.shown or self.lens end

--------------------------------------------------
-- MARK: Out of the camera's way
--------------------------------------------------

-- The player's own ped (and what it holds) is not drawn on their game while the camera is inside it
-- or looks through it at the prop. Everyone else sees it at work.

local function inTheWay(ped, pose, aim)
    local dir = aim and norm(aim - pose.eye)
    local reach = aim and len(aim - pose.eye) or 0.0

    for _, bone in ipairs(BONES) do
        local at = GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
        local r = at - pose.eye

        if len(r) < CLEAR then return true end

        if dir then
            local t = dot(r, dir)

            if t > 0.0 and t < reach and len(r - dir * t) < 0.28 then return true end
        end
    end

    return false
end

local function hideTick(s)
    local ped = s.ped
    local pose = s.shown or s.lens

    if inTheWay(ped, pose, s.aim) then
        SetEntityLocallyInvisible(ped)

        for _, entity in ipairs(s.carried) do
            if DoesEntityExist(entity) then SetEntityLocallyInvisible(entity) end
        end
    end
end

local function carried(ped)
    local out = {}
    local weapon = GetCurrentPedWeaponEntityIndex(ped)

    if weapon and weapon ~= 0 then out[#out + 1] = weapon end

    for _, object in ipairs(GetGamePool("CObject")) do
        if IsEntityAttachedToEntity(object, ped) then out[#out + 1] = object end
    end

    return out
end

--------------------------------------------------
-- MARK: The cursor
--------------------------------------------------

-- The game's own cursor where the mouse puts it; a pad's right stick moves it. A button already held
-- when the close-up opens has to be let go before it presses anything, and nothing presses while
-- the camera glides in.

local STICK = 0.55

--- This frame's input: x, y (0-1), dx, dy, down, pressed, released, drop (right click), wheel,
--- moving (the camera is gliding).
function S:input()
    local x, y, down
    local p = self.point

    if self.virtual then
        x, y, down = self.virtual.x, self.virtual.y, self.virtual.down == true
    elseif IsUsingKeyboard(0) then
        x, y = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
        down = IsDisabledControlPressed(0, 24)
    else
        local step = STICK * GetFrameTime()

        x = C.clamp(p.x + GetDisabledControlNormal(0, 1) * step)
        y = C.clamp(p.y + GetDisabledControlNormal(0, 2) * step * aspect())
        down = IsDisabledControlPressed(0, 24) or IsDisabledControlPressed(0, 201)
        SetCursorLocation(F(x), F(y))
    end

    local dx, dy

    if self.held then
        dx, dy = x - self.held.x, y - self.held.y

        if not self.virtual then SetCursorLocation(F(self.held.x), F(self.held.y)) end

        x, y = self.held.x, self.held.y
    else
        dx, dy = x - p.x, y - p.y
    end

    if self.latch and not down then self.latch = false end

    local live = not self.latch and not self.entering and not self.over
    local press = live and down
    local input = {
        x = x, y = y, dx = dx, dy = dy, down = press,
        pressed = press and not self.wasDown, released = self.wasDown and not press,
        drop = live and IsDisabledControlJustPressed(0, 25),
        wheel = (IsDisabledControlJustPressed(0, 15) and 1 or 0) - (IsDisabledControlJustPressed(0, 14) and 1 or 0),
        moving = self.move ~= nil,
    }

    p.x, p.y, self.wasDown = x, y, press

    return input
end

--- The cursor's hand: "press", "grab", "hold", or nil for the arrow.
function S:cursor(kind) self.sprite = SPRITES[kind] or 1 end

--- Keeps the cursor still at (x, y) while a hand works something by feel (input.dx, dy still say how
--- the mouse moved). No spot lets it go.
function S:hold(x, y) self.held = x and y and { x = x, y = y } or nil end

--- The ray under the cursor, from the camera as it is on the screen.
function S:ray(input) return C.ray(self:view(), input.x, input.y) end

--- Which of `parts` is under the cursor (see C.under), and where.
function S:under(input, parts)
    local origin, dir = self:ray(input)

    return C.under(origin, dir, parts)
end

--- The nearest of `anchors` (world points) to the cursor on the screen within `radius` (screen
--- heights, 0.05): index and gap. For parts too small or too close together to hit with a ray.
function S:nearest(input, anchors, radius)
    local pose, a = self:view(), aspect()
    local best, gap = nil, radius or 0.05

    for i, at in ipairs(anchors) do
        local x, y = C.screen(pose, at)

        if x then
            local d = math.sqrt(((x - input.x) * a) ^ 2 + (y - input.y) ^ 2)

            if d < gap then best, gap = i, d end
        end
    end

    return best, gap
end

--- Outlines the part the hand is over (nil clears it); a ped is never outlined. It stays until the
--- next call, and a hint that is breathing goes first.
function S:outline(entity, colour)
    self.lit = entity and { entity = entity, colour = colour } or nil

    if self.hinting then return not (entity and IsEntityAPed(entity)) end

    return C.outline(entity, colour)
end

--- A first-use hint: the outline on `entity` breathes for `ms` (1600) so the player sees where to
--- start. Nothing is drawn on the screen.
function S:hint(entity, ms)
    self.hinting = { entity = entity, till = now() + (ms or 1600) }
end

--------------------------------------------------
-- MARK: Feedback
--------------------------------------------------

--- A point in the host's frame, in the world.
function S:at(p) return self.frame and C.toWorld(self.frame, p) or p end

local function where(s, at) return at end

--- A sound, from an entity, a world point or the screen (nil). opts: set (sound set), bank (loaded
--- first, released when the session ends), loop (kept until :stopSound or the end), range.
--- Gives back the sound id.
function S:sound(name, at, opts)
    opts = opts or {}

    if opts.bank and not self.banks[opts.bank] then
        if not C.load("bank", opts.bank, 1500) then return nil end

        self.banks[opts.bank] = true
    end

    local id = GetSoundId()
    local set = opts.set

    at = where(self, at)

    if type(at) == "number" then
        PlaySoundFromEntity(id, name, at, set, false, 0)
    elseif at then
        PlaySoundFromCoord(id, name, F(at.x), F(at.y), F(at.z), set, false, I(opts.range or 6), false)
    else
        PlaySoundFrontend(id, name, set, true)
    end

    self.sounds[id] = { loop = opts.loop, at = now() }

    return id
end

function S:stopSound(id)
    if not self.sounds[id] then return end

    StopSound(id)
    ReleaseSoundId(id)
    self.sounds[id] = nil
end

local function soundTick(s)
    for id, sound in pairs(s.sounds) do
        if not sound.loop and now() - sound.at > 100 and HasSoundFinished(id) then
            ReleaseSoundId(id)
            s.sounds[id] = nil
        end
    end
end

--- A particle effect. opts: at (world) or on (entity) + offset, rot, scale, loop (gives back the
--- handle; it is faded out and removed when the session ends), colour = { r, g, b } (0-1), alpha.
function S:fx(asset, name, opts)
    opts = opts or {}

    if not C.load("fx", asset, 1500) then return nil end

    local rot, scale = opts.rot or v(0.0, 0.0, 0.0), F(opts.scale or 1.0)
    local handle

    UseParticleFxAsset(asset)

    if opts.on then
        local off = opts.offset or v(0.0, 0.0, 0.0)

        if opts.loop then
            handle = StartParticleFxLoopedOnEntity(name, opts.on, F(off.x), F(off.y), F(off.z), F(rot.x), F(rot.y), F(rot.z), scale, false, false, false)
        else
            handle = StartParticleFxNonLoopedOnEntity(name, opts.on, F(off.x), F(off.y), F(off.z), F(rot.x), F(rot.y), F(rot.z), scale, false, false, false)
        end
    else
        local at = where(self, opts.at) or GetEntityCoords(self.entity)

        if opts.loop then
            handle = StartParticleFxLoopedAtCoord(name, F(at.x), F(at.y), F(at.z), F(rot.x), F(rot.y), F(rot.z), scale, false, false, false, false)
        else
            handle = StartParticleFxNonLoopedAtCoord(name, F(at.x), F(at.y), F(at.z), F(rot.x), F(rot.y), F(rot.z), scale, false, false, false)
        end
    end

    if opts.loop and handle and handle ~= 0 then
        if opts.colour then SetParticleFxLoopedColour(handle, F(opts.colour[1]), F(opts.colour[2]), F(opts.colour[3]), false) end
        if opts.alpha then SetParticleFxLoopedAlpha(handle, F(opts.alpha)) end

        self.loops[handle] = { alpha = opts.alpha or 1.0 }
    end

    return handle
end

local function killLoop(handle)
    if DoesParticleFxLoopedExist(handle) then
        StopParticleFxLooped(handle, false)
        RemoveParticleFx(handle, false)
    end
end

--- Fades a looped effect out over `ms` (250), then stops and removes it.
function S:fxStop(handle, ms)
    local loop = self.loops[handle]

    if not loop then return end

    self.loops[handle] = nil
    ms = ms or 250

    if ms <= 0 or self.stopping then return killLoop(handle) end

    CreateThread(function()
        local start = now()

        while now() - start < ms and DoesParticleFxLoopedExist(handle) do
            SetParticleFxLoopedAlpha(handle, F(loop.alpha * (1.0 - (now() - start) / ms)))
            Wait(0)
        end

        killLoop(handle)
    end)
end

--- A real light for `ms` (or until the end when nil): at (world), colour = { r, g, b } 0-255, range,
--- intensity. It fades out over its last quarter.
function S:glow(at, colour, range, intensity, ms)
    self.lights[#self.lights + 1] = {
        at = at, colour = colour or { 255, 220, 170 }, range = range or 0.4, intensity = intensity or 2.0,
        from = now(), till = ms and now() + ms or nil,
    }
end

local function lightTick(s)
    local t = now()

    for i = #s.lights, 1, -1 do
        local l = s.lights[i]

        if l.till and t >= l.till then
            table.remove(s.lights, i)
        else
            local fade = 1.0

            if l.till then
                local quarter = (l.till - l.from) * 0.25

                fade = C.clamp((l.till - t) / math.max(1, quarter))
            end

            local at = type(l.at) == "function" and l.at() or l.at

            DrawLightWithRange(F(at.x), F(at.y), F(at.z), I(l.colour[1]), I(l.colour[2]), I(l.colour[3]), F(l.range), F(l.intensity * fade))
        end
    end
end

--- The little reward a step gets when it lands: opts sound, set, bank, at, fx = { asset, name, scale },
--- kick (strength), light = { colour, range, intensity, ms }.
function S:juice(opts)
    if opts.sound then self:sound(opts.sound, opts.at or self.entity, { set = opts.set, bank = opts.bank }) end

    if opts.fx then
        local at = where(self, opts.at)

        self:fx(opts.fx[1], opts.fx[2], { at = type(at) ~= "number" and at or nil, on = type(at) == "number" and at or nil, scale = opts.fx[3] })
    end

    if opts.kick then self:kick(opts.kick) end

    if opts.light then
        local at = where(self, opts.at)

        if type(at) == "number" then at = GetEntityCoords(at) end
        if at then self:glow(at, opts.light.colour, opts.light.range, opts.light.intensity, opts.light.ms or 220) end
    end
end

--------------------------------------------------
-- MARK: Animation
--------------------------------------------------

--- Plays a clip on the player. opts: flag (C.ANIM.WORK), blendIn (8), blendOut (-8), ms (-1), at
--- (0-1 start). It is stopped when the session ends. False when the dict never loaded.
function S:anim(dict, clip, opts)
    opts = opts or {}

    if not C.load("dict", dict) then return false end

    TaskPlayAnim(self.ped, dict, clip, F(opts.blendIn or 8.0), F(opts.blendOut or -8.0), I(opts.ms or -1), I(opts.flag or C.ANIM.WORK), F(opts.at or 0.0), false, false, false)

    self.clips[dict .. "|" .. clip] = { dict = dict, clip = clip }

    return true
end

function S:stopAnim(dict, clip, blend)
    local key = dict .. "|" .. clip

    if not self.clips[key] then return end

    StopAnimTask(self.ped, dict, clip, F(blend or 2.0))
    self.clips[key] = nil
end

--- A networked synchronised scene at `at` (world) turned `rot` (degrees, world): ped = { dict, clip,
--- flags (C.SCENE.PED), blendIn, blendOut }, props = { { entity, dict, clip, flags }, ... }, hold,
--- looped, rate. Gives back its network id (see :phase). It is stopped when the session ends.
function S:scene(opts)
    local at, rot = opts.at, opts.rot or v(0.0, 0.0, 0.0)
    local id = NetworkCreateSynchronisedScene(F(at.x), F(at.y), F(at.z), F(rot.x), F(rot.y), F(rot.z), 2, opts.hold == true, opts.looped == true, F(1.0), F(0.0), F(opts.rate or 1.0))

    if opts.ped then
        local p = opts.ped

        if not C.load("dict", p.dict) then return nil end

        NetworkAddPedToSynchronisedScene(self.ped, id, p.dict, p.clip, F(p.blendIn or 8.0), F(p.blendOut or -8.0), I(p.flags or C.SCENE.PED), 0, F(1000.0), 0)
    end

    for _, prop in ipairs(opts.props or {}) do
        if C.load("dict", prop.dict) then
            NetworkAddEntityToSynchronisedScene(prop.entity, id, prop.dict, prop.clip, F(prop.blendIn or 4.0), F(prop.blendOut or -4.0), I(prop.flags or 0))
        end
    end

    NetworkStartSynchronisedScene(id)
    self.scenes[id] = true

    return id
end

--- A scene's phase (0-1), nil until it is running on this game.
function S:phase(id)
    local scene = NetworkGetLocalSceneFromNetworkId(id)

    if scene == -1 or not IsSynchronizedSceneRunning(scene) then return nil end

    return GetSynchronizedScenePhase(scene)
end

function S:stopScene(id)
    if not self.scenes[id] then return end

    NetworkStopSynchronisedScene(id)
    self.scenes[id] = nil
end

--------------------------------------------------
-- MARK: Props the session made
--------------------------------------------------

--- A prop on this game only, posed in the host's frame: at, y, z (its own axes, unit; default the
--- host's), deleted when the session is over and the camera is out. Collision off, frozen.
function S:prop(model, at, y, z)
    if not C.load("model", model) then return nil end

    local hash = type(model) == "number" and model or joaat(model)
    local w = self.frame and C.toWorld(self.frame, at) or at
    local entity = CreateObjectNoOffset(hash, F(w.x), F(w.y), F(w.z), false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not entity or entity == 0 then return nil end

    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    self.props[entity] = true

    if self.frame then self:pose(entity, at, y, z) end

    return entity
end

--- Deletes a prop the session made before the session ends (the cash once it is taken).
function S:drop(entity)
    if not self.props[entity] then return end

    self.props[entity] = nil

    if self.lit and self.lit.entity == entity then self:outline(nil) end
    if self.hinting and self.hinting.entity == entity then self.hinting = nil end
    if outlined == entity then C.outline(nil) end
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

--- Poses an entity in frame `f` (nil: the world): `at` its origin, `y` and `z` its own Y and Z (unit,
--- square; the frame's own when nil), `scale` its size.
function C.pose(f, entity, at, y, z, scale)
    local w = f and C.toWorld(f, at) or at
    local Y = f and C.dirToWorld(f, y or v(0.0, 1.0, 0.0)) or (y or v(0.0, 1.0, 0.0))
    local Z = f and C.dirToWorld(f, z or v(0.0, 0.0, 1.0)) or (z or v(0.0, 0.0, 1.0))
    local X = cross(Y, Z)
    local s = scale or 1.0

    SetEntityMatrix(entity, F(Y.x * s), F(Y.y * s), F(Y.z * s), F(X.x * s), F(X.y * s), F(X.z * s), F(Z.x * s), F(Z.y * s), F(Z.z * s), F(w.x), F(w.y), F(w.z))
end

--- Poses a prop in the host's frame (see C.pose).
function S:pose(entity, at, y, z, scale) C.pose(self.frame, entity, at, y, z, scale) end

--------------------------------------------------
-- MARK: Parts moved by hand
--------------------------------------------------

-- The two motions most parts make: along a line (a card into a slot, a magazine into its well, a
-- drawer) and round an axis (a cap, a valve, a suppressor screwing home). Each poses the part every
-- frame from a spring, so it moves with weight, and waits until the part comes to rest.

local function frameDt(s)
    local t = now()
    local dt = math.min(0.05, (t - (s.lastStep or t)) * 0.001)

    s.lastStep = t

    return dt
end

--- Lets the player move a part along a line: grab it and pull, or just click it. Let go past `finish`
--- (or after a click) and it carries on to the end by itself; let go short and it slides back. spec:
---   entity        the part's prop, posed along the line every frame
---   from, to      its origin at the start and at the end (host frame)
---   y, z, scale   its axes and scale on the way (see S:pose)
---   finish        0-1, how far a pull has to get before it goes the rest of the way itself (0.35)
---   click         false when a click alone must not send it
---   grabbed       true when the press that picked it up is the grab (it is already in the hand)
---   pad           how much bigger than the part its grab box is (0.015 m)
---   hint          true: its outline breathes until it is first grabbed
---   path(t)       where it is at t (host frame) when that is not on the line: a part resting on a bench
---                 lifts into line before it slides home. The hand still pulls along from-to.
---   on(t, held)   each frame, with how far along it is (0-1)
--- Waits until it rests: 1 at the end, 0 back at the start (only when it was handed over grabbed; a
--- part the player has to pick up again waits for them), nil when the session ended.
function S:drag(spec)
    local slide = C.slide(spec.from, spec.to, { at = spec.at })
    local part = { entity = spec.entity, pad = spec.pad or 0.015 }
    local finish = spec.finish or 0.35
    local held, from, let = spec.grabbed == true, slide.s.x, false

    if spec.hint then self:hint(spec.entity) end

    self.lastStep = now()

    while not self.over do
        local dt = frameDt(self)
        local input = self:input()

        if held then
            self:cursor("grab")
            self:outline(spec.entity)

            if input.down then
                if not input.moving then
                    local o, d = self:ray(input)

                    slide:follow(C.toLocal(self.frame, o), C.dirToLocal(self.frame, d))
                end
            else
                held, let = false, true
                slide:release()

                local clicked = spec.click ~= false and math.abs(slide.s.x - from) < 0.03

                slide.s.to = (clicked or slide.s.x >= finish) and 1.0 or 0.0
                self:outline(nil)
            end
        elseif not input.moving and not let then
            if self:under(input, { part }) then
                self:cursor("press")
                self:outline(spec.entity)

                if input.pressed then
                    held, from = true, slide.s.x
                    self.hinting = nil
                end
            else
                self:outline(nil)
            end
        end

        local x, rest = slide:update(dt)

        self:pose(spec.entity, spec.path and spec.path(x) or slide:at(), spec.y, spec.z, spec.scale)

        if spec.on then spec.on(x, held) end

        if rest and let then
            if rest >= 1.0 or spec.grabbed then return rest end

            let = false
        end

        Wait(0)
    end
end

-- `p` turned `deg` degrees round the unit axis `k` (right hand).
local function turn(p, k, deg)
    local a = math.rad(deg)
    local c, s = math.cos(a), math.sin(a)

    return p * c + cross(k, p) * s + k * (dot(k, p) * (1.0 - c))
end

C.turn = turn

-- How many degrees a mouse move turns a part round `axis` at `at` (world): the move across the axis
-- as it is on the screen, so the part rolls the way the hand pushes it.
local function across(s, input, at, axis)
    local pose, a = s:view(), aspect()
    local x0, y0 = C.screen(pose, at)
    local x1, y1 = C.screen(pose, at + axis * 0.05)

    if not x0 or not x1 then return input.dy * 600.0 end

    local ax, ay = (x1 - x0) * a, y1 - y0
    local l = math.sqrt(ax * ax + ay * ay)

    -- Looking down the axis: turning it is circling it, and across the screen is near enough.
    if l < 1e-3 then return input.dx * a * 600.0 end

    local px, py = -ay / l, ax / l

    if py < 0 or (math.abs(py) < 0.2 and px < 0) then px, py = -px, -py end

    return (input.dx * a * px + input.dy * py) * 600.0
end

--- Lets the player turn a part round an axis: hold it and drag across it, a tick at every detent. A
--- turn back undoes it. spec:
---   entity        the part's prop
---   at            its origin before it turns (host frame); travel = how far it moves by the last
---                 degree (a thread drawing it in)
---   axis          what it turns round (host frame, unit, through `at`); y, z its own axes before it
---                 turns; scale
---   turns         degrees to the end (270); detents in a full turn (12)
---   sound         { name, set } for each detent
---   grabbed, hint, pad, on(angle, held) as S:drag
--- Waits until it is all the way round: true, or nil when the session ended.
function S:twist(spec)
    local goal = spec.turns or 270.0
    local dial = C.dial({ detents = spec.detents or 12, min = 0.0, max = goal })
    local part = { entity = spec.entity, pad = spec.pad or 0.015 }
    local held, spot = spec.grabbed == true, nil
    local axis = norm(spec.axis)
    local travel = spec.travel or v(0.0, 0.0, 0.0)
    local y0, z0 = spec.y or v(0.0, 1.0, 0.0), spec.z or v(0.0, 0.0, 1.0)

    if spec.hint then self:hint(spec.entity) end

    self.lastStep = now()

    while not self.over do
        local dt = frameDt(self)
        local input = self:input()

        if held then
            self:cursor("hold")
            self:outline(spec.entity)

            if input.down then
                if not spot then
                    spot = { x = input.x, y = input.y }
                    self:hold(spot.x, spot.y)
                elseif not input.moving then
                    dial:turn(across(self, input, self:at(spec.at), C.dirToWorld(self.frame, axis)))
                end
            else
                held, spot = false, nil
                self:hold(nil)
                dial:release()
                self:outline(nil)
            end
        elseif not input.moving then
            if self:under(input, { part }) then
                self:cursor("press")
                self:outline(spec.entity)

                if input.pressed then
                    held = true
                    self.hinting = nil
                end
            else
                self:outline(nil)
            end
        end

        local angle, crossed = dial:update(dt)

        if crossed > 0 and spec.sound then self:sound(spec.sound[1], spec.entity, { set = spec.sound[2] }) end

        self:pose(spec.entity, spec.at + travel * (angle / goal), turn(y0, axis, angle), turn(z0, axis, angle), spec.scale)

        if spec.on then spec.on(angle, held) end

        if angle >= goal - 0.01 then
            self:hold(nil)
            self:outline(nil)

            return true
        end

        Wait(0)
    end
end

--------------------------------------------------
-- MARK: Each frame
--------------------------------------------------

local function watchdog(s)
    local ped = s.ped
    local why = blocked(ped)

    if why then return why end
    if s.entity and not DoesEntityExist(s.entity) then return "gone" end
    if GetSelectedPedWeapon(ped) ~= UNARMED then return "weapon" end
    if s.entity and s.leave and len(GetEntityCoords(ped) - GetEntityCoords(s.entity)) > s.leave then return "far" end
end

-- A close key counts once it has been seen up, then down, then up again: a key still held from
-- whatever opened the close-up never closes it.
local function cancelTick(s)
    local fire = false

    for _, key in ipairs(C.CANCEL) do
        local down, state = IsDisabledControlPressed(0, key), s.keys[key]

        if not down then
            if state == "down" and s.cancellable then fire = true end

            s.keys[key] = "up"
        elseif state == "up" then
            s.keys[key] = "down"
        end
    end

    return fire
end

local function tick(s, dt)
    DisableAllControlActions(0)
    EnableControlAction(0, 245, true) -- chat
    EnableControlAction(0, 249, true) -- push to talk

    if not s.fixed and DoesEntityExist(s.entity) then s.frame = C.frame(s.entity) end

    camTick(s, dt)
    hideTick(s)
    soundTick(s)
    lightTick(s)

    if not s.over then
        SetMouseCursorActiveThisFrame()
        SetMouseCursorSprite(s.sprite)

        if s.hinting then
            local h = s.hinting

            if now() >= h.till or not DoesEntityExist(h.entity) then
                s.hinting = nil
                C.outline(s.lit and s.lit.entity, s.lit and s.lit.colour)
            else
                local pulse = 0.5 + 0.5 * math.sin((now() - h.till) * 0.008)

                C.outline(h.entity, { 255, 255, 255, 60 + 120 * pulse })
                SetEntityDrawOutlineColor(255, 255, 255, I(60 + 120 * pulse))
            end
        end

        local why = watchdog(s)

        if why then
            s:cancel(why)
        elseif cancelTick(s) then
            s:cancel("cancel")
        end
    end

    if s.entering and not s.move then s.entering = false end

    s.sprite = 1
end

--------------------------------------------------
-- MARK: Opening and closing
--------------------------------------------------

-- How far apart two points are on the ground: the stand spot is in the prop's frame, so its height is
-- the prop's, not the ped's.
local function apart(a, b)
    local dx, dy = a.x - b.x, a.y - b.y

    return math.sqrt(dx * dx + dy * dy)
end

local function walkTo(s, stand)
    local f = s.frame
    local at = C.toWorld(f, stand.at)
    local heading = math.deg(math.atan(-f.forward.x, f.forward.y)) + (stand.heading or 0.0)
    local ped = s.ped

    if apart(GetEntityCoords(ped), at) > 0.12 then
        TaskGoStraightToCoord(ped, F(at.x), F(at.y), F(at.z), F(1.0), I(C.TIMING.walk), F(heading), F(0.05))
    else
        TaskAchieveHeading(ped, F(heading), 800)
    end

    local deadline = now() + C.TIMING.walk + 300
    local rested = false -- the move keys let go since the walk began (a key held running up is not a push)

    while now() < deadline do
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true)
        EnableControlAction(0, 249, true)

        -- A close key or a fresh push on the move keys backs out of the walk; the player keeps their legs.
        local why = watchdog(s)
        local pushed = math.abs(GetDisabledControlNormal(0, 30)) > 0.5 or math.abs(GetDisabledControlNormal(0, 31)) > 0.5

        rested = rested or not pushed

        if not why and s.cancellable and (cancelTick(s) or (pushed and rested)) then why = "cancel" end

        if why then
            if not blocked(ped) then ClearPedTasks(ped) end

            return false, why
        end

        local d = apart(GetEntityCoords(ped), at)
        local turn = math.abs(C.wrap(GetEntityHeading(ped) - heading))

        if d < 0.15 and turn < 12.0 then break end

        if d < 0.15 and GetScriptTaskStatus(ped, TASK_HEADING) == 7 and GetScriptTaskStatus(ped, TASK_WALK) == 7 then
            TaskAchieveHeading(ped, F(heading), 800)
        end

        Wait(0)
    end

    return true
end

local function restorePlayer(s)
    local ped = s.ped

    if s.weapon and s.weapon ~= UNARMED and HasPedGotWeapon(ped, s.weapon, false) then
        SetCurrentPedWeapon(ped, s.weapon, true)
    end

    if s.froze then FreezeEntityPosition(ped, false) end

    C.outline(nil)

    if s.hud and gg.hud then gg.hud.show() end
    if s.tool then LocalPlayer.state:set("ggTool", nil, false) end
end

local function runAll(list)
    for i = #list, 1, -1 do pcall(list[i]) end

    for i = #list, 1, -1 do list[i] = nil end
end

local function stopActions(s)
    for id in pairs(s.sounds) do
        StopSound(id)
        ReleaseSoundId(id)
    end

    s.sounds = {}

    for handle in pairs(s.loops) do
        if s.stopping then killLoop(handle) else s:fxStop(handle, 200) end
    end

    for id in pairs(s.scenes) do NetworkStopSynchronisedScene(id) end

    s.scenes = {}

    for _, c in pairs(s.clips) do
        StopAnimTask(s.ped, c.dict, c.clip, F(2.0))
        RemoveAnimDict(c.dict)
    end

    s.clips, s.lights, s.hinting, s.held, s.lit = {}, {}, nil, nil, nil
    C.outline(nil)
    runAll(s.early)
end

local function dropProps(s)
    for entity in pairs(s.props) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end

    s.props = {}

    for bank in pairs(s.banks) do ReleaseNamedScriptAudioBank(bank) end

    s.banks = {}
    runAll(s.late)
end

local function dropCam(s)
    if not s.cam then return end

    RenderScriptCams(false, false, 0, true, true)

    if DoesCamExist(s.cam) then DestroyCam(s.cam, false) end

    s.cam = nil
end

-- The normal way out: everything the session was doing stops, the camera glides back to the live
-- gameplay camera (still hiding the ped while it passes through it), then the props it made go.
local function close(s)
    stopActions(s)

    if s.cam then
        local mode = GetFollowPedCamViewMode()

        if mode == 4 and s.relative then
            SetGameplayCamRelativeHeading(F(s.relative.heading))
            SetGameplayCamRelativePitch(F(s.relative.pitch), F(1.0))
        end

        local out = gameplayPose()

        if len(out.eye - s:view().eye) <= CUT then
            s.queue = {}
            startMove(s, out, s.out or C.TIMING.leave, function(u) return u * u end, C.smooth)
            s.move.live = true

            local last = now()

            while s.move do
                local t = now()

                DisableAllControlActions(0)
                EnableControlAction(0, 245, true)
                EnableControlAction(0, 249, true)
                camTick(s, (t - last) * 0.001)
                hideTick(s)
                last = t
                Wait(0)
            end
        end

        dropCam(s)
    end

    dropProps(s)
    restorePlayer(s)
end

-- The resource is stopping: no waits are possible, so everything goes at once, the camera first.
local function hardStop(s)
    s.stopping, s.over, s.reason = true, true, s.reason or "stopped"
    dropCam(s)
    pcall(stopActions, s)
    pcall(dropProps, s)
    pcall(restorePlayer, s)
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() or not current then return end

    local s = current

    current = nil
    hardStop(s)
end)

--- Opens a close-up on `opts.entity` and runs `fn(session)` in it, from a thread of the caller's.
--- opts:
---   entity        the prop worked (its frame poses everything)
---   frame         a frame of its own instead (C.frameOf(origin, heading)), for a spot with no prop
---   shot          the first shot (see S:frameShot), the whole model square on when nil
---   stand         { at = vector3 in the prop's frame, heading = degrees from the prop's } to walk to first
---   reach         how near the player must be to open (2.5 m)
---   leave         how far they may get before it ends ("far"), 3 m
---   enter, out    glide times (C.TIMING)
---   drift         0-1, the camera breathing while it holds still (0.6)
---   dof           true for a shallow depth of field (the player's Post FX setting decides)
---   freeze        true to freeze the player in place
---   hud           false to leave the HUD up
---   cancellable   false to ignore the close keys
--- Gives back what fn returned and why it ended: "done", "cancel", "vehicle", "dead", "ragdoll",
--- "falling", "swimming", "climbing", "weapon", "far", "gone", "busy", "blocked" or "error".
function C.run(opts, fn)
    if current then return nil, "busy" end
    if LocalPlayer.state.ggTool then return nil, "busy" end

    local ped = PlayerPedId()
    local entity = opts.entity

    if entity and not DoesEntityExist(entity) then return nil, "gone" end

    local why = blocked(ped)

    if why then return nil, why end

    if entity and len(GetEntityCoords(ped) - GetEntityCoords(entity)) > (opts.reach or 2.5) then return nil, "far" end

    local s = setmetatable({
        ped = ped, entity = entity, frame = opts.frame or (entity and C.frame(entity)) or C.frameOf(GetEntityCoords(ped), GetEntityHeading(ped)),
        fixed = opts.frame ~= nil or not entity,
        leave = opts.leave or 3.0, drift = opts.drift or 0.6, dof = opts.dof == true, out = opts.out,
        cancellable = opts.cancellable ~= false, keys = {},
        point = { x = 0.5, y = 0.5 }, latch = true, wasDown = false, sprite = 1, entering = true,
        early = {}, late = {}, sounds = {}, loops = {}, clips = {}, scenes = {}, props = {}, banks = {}, lights = {},
        queue = {}, over = false, reason = nil,
    }, S)

    current = s

    local ok, result = pcall(function()
        LocalPlayer.state:set("ggTool", true, false)
        s.tool = true

        if opts.hud ~= false and gg.hud then
            gg.hud.hide()
            s.hud = true
        end

        s.weapon = GetSelectedPedWeapon(ped)

        if s.weapon ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end

        if opts.stand and entity then
            local walked, stop = walkTo(s, opts.stand)

            if not walked then
                s:cancel(stop)

                return nil
            end
        end

        if opts.freeze then
            FreezeEntityPosition(ped, true)
            s.froze = true
        end

        s.carried = carried(ped)
        s.relative = { heading = GetGameplayCamRelativeHeading(), pitch = GetGameplayCamRelativePitch() }

        -- A still copy of what is on the screen, cut to (so nothing moves), then the session's own glide.
        local rot = GetFinalRenderedCamRot(2)

        s.lens = poseOf(GetFinalRenderedCamCoord(), (C.basis(rot)), GetFinalRenderedCamFov())
        s.cam = CreateCamWithParams(s.dof and "DEFAULT_SCRIPTED_FLY_CAMERA" or "DEFAULT_SCRIPTED_CAMERA",
            F(s.lens.eye.x), F(s.lens.eye.y), F(s.lens.eye.z), F(rot.x), F(rot.y), F(rot.z), F(s.lens.fov), false, 2)
        SetCamNearClip(s.cam, F(0.02))

        if s.dof then
            SetCamUseShallowDofMode(s.cam, true)
            SetCamNearDof(s.cam, F(0.05))
            SetCamFarDof(s.cam, F(3.0))
            SetCamDofStrength(s.cam, F(0.6))
        end

        setCam(s, s.lens)
        SetCamActive(s.cam, true)
        RenderScriptCams(true, false, 0, true, true)
        SetCursorLocation(0.5, 0.5)

        local first = opts.shot or {}
        local spec = {}

        for k, value in pairs(first) do spec[k] = value end

        spec.ms = opts.enter or C.TIMING.enter

        s:shot(spec)

        CreateThread(function()
            local last = now()

            while current == s and not s.closing do
                local t = now()

                tick(s, (t - last) * 0.001)
                last = t
                Wait(0)
            end
        end)

        return fn(s)
    end)

    if not ok then
        s.reason = "error"
        s.error = result
        print(("^1[gg.closeup] %s^7"):format(tostring(result)))
        result = nil
    end

    -- Still the current session while the camera glides back out, so nothing opens over it.
    if current == s then
        s.closing, s.over = true, true
        s.reason = s.reason or "done"

        local closed, err = pcall(close, s)

        if not closed then
            print(("^1[gg.closeup] closing: %s^7"):format(tostring(err)))
            hardStop(s)
        end

        if current == s then current = nil end
    end

    return result, s.reason
end

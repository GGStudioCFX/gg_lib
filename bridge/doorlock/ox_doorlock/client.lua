
gg.doorlock = gg.doorlock or {}

local NAME = "ox_doorlock"

--------------------------------------------------
-- MARK: Guarded calls
--------------------------------------------------

local seen = {}

local function invoke(fn, ...)
    return exports[NAME][fn](nil, ...)
end

local function call(fn, ...)
    if GetResourceState(NAME) ~= "started" then return nil end

    local ok, result = pcall(invoke, fn, ...)

    if ok then return result end

    if not seen[fn] then
        seen[fn] = true

        print(("^1[gg_lib] %s:%s() threw. That is %s's code, not gg_lib's -- send them this:^0\n%s")
            :format(NAME, fn, NAME, tostring(result)))
    end

    return nil
end

--------------------------------------------------
-- MARK: Doors
--------------------------------------------------

-- The client holds no door list it can read, so a door by id or name is asked
-- of this resource's own server, which answers without access lists.
local function lookup(door)
    if type(door) ~= "number" and (type(door) ~= "string" or door == "") then return nil end
    if GetResourceState(NAME) ~= "started" then return nil end

    local ok, found = pcall(gg.callback.await, GetCurrentResourceName() .. ":doorlock:door", door)

    return ok and type(found) == "table" and found or nil
end

gg.doorlock.resource = NAME

gg.doorlock.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.doorlock.getDoor = lookup

-- By name only, as the server bridge has it (the server tells a name from an id).
gg.doorlock.getDoorByName = function(name)
    if type(name) ~= "string" or name == "" then return nil end

    return lookup(name)
end

gg.doorlock.isLocked = function(door)
    local found = lookup(door)

    if not found then return nil end

    return found.locked == true
end

-- A player's request, so ox_doorlock checks their groups, items and passcode and
-- tells them if they are refused. true means it was asked, not that it was allowed.
gg.doorlock.setLocked = function(door, locked)
    local id = type(door) == "number" and door or nil

    if not id then
        local found = lookup(door)

        id = found and found.id
    end

    if not id or GetResourceState(NAME) ~= "started" then return false end

    TriggerServerEvent("ox_doorlock:setState", id, locked and 1 or 0)

    return true
end

-- state: true / 1 / "locked" locks, anything else unlocks. A player's request, as setLocked.
gg.doorlock.setState = function(door, state)
    return gg.doorlock.setLocked(door, state == true or state == 1 or state == "locked")
end

local function reachable(door)
    return type(door.distance) == "number" and type(door.maxDistance) == "number"
        and door.distance < door.maxDistance
end

-- ox_doorlock keeps a closest door until none is within 20 m, so one past its
-- interact distance can still be returned; reachable says whether it is usable.
gg.doorlock.closest = function()
    local door = call("getClosestDoor")

    if type(door) ~= "table" or door.id == nil then return nil end

    return {
        id          = door.id,
        name        = door.name,
        locked      = door.state == 1,
        coords      = door.coords,
        entity      = door.entity,
        distance    = door.distance,
        maxDistance = door.maxDistance,
        reachable   = reachable(door),
    }
end

-- Toggles the closest door the way its E key does, and only within the same reach.
gg.doorlock.useClosest = function()
    local door = call("getClosestDoor")

    if type(door) ~= "table" or not reachable(door) then return false end

    call("useClosestDoor")

    return true
end

-- Runs ox_doorlock's own skill check and animation, and waits for them.
-- true means the attempt was made; the door's state says how it went.
gg.doorlock.pickClosest = function()
    local door = call("getClosestDoor")

    if type(door) ~= "table" or not door.lockpick or not reachable(door) then return false end

    call("pickClosestDoor")

    return true
end

gg.doorlock.idOf = function(entity)
    if type(entity) ~= "number" or entity == 0 then return nil end

    local id = call("getDoorIdFromEntity", entity)

    if id ~= nil then return id end

    local ok, state = pcall(function() return Entity(entity).state.doorId end)

    return ok and state or nil
end

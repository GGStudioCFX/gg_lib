gg.doorlock = gg.doorlock or {}

local NAME = "ox_doorlock"
local NAME_MAX = 50        -- ox_doorlock's name column is varchar(50)
local NEAR = 0.5           -- metres: a saved door this close to a new one is the same door

-- Kept outside this file: it can load twice in one resource (a door lock that
-- starts later), and a listener added before then must still hear changes.
GG_DOORLOCK_LISTENERS = GG_DOORLOCK_LISTENERS or {}

--------------------------------------------------
-- MARK: Guarded calls
--------------------------------------------------

-- Looking an export up is itself what throws when it does not exist, so the
-- lookup happens inside the guard. A throw is said once per export, with the
-- line to send to whoever owns the code that threw.
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

-- Whether this ox_doorlock has an export, asked without calling it (and without a warning).
local function has(fn)
    if GetResourceState(NAME) ~= "started" then return false end

    return (pcall(function() return exports[NAME][fn] end))
end

--------------------------------------------------
-- MARK: Doors
--------------------------------------------------

local function shape(door)
    if type(door) ~= "table" or door.id == nil then return nil end

    return {
        id          = door.id,
        name        = door.name,
        locked      = door.state == 1,
        coords      = door.coords,
        groups      = door.groups,
        items       = door.items,
        characters  = door.characters,
        maxDistance = door.maxDistance,
    }
end

-- A door is its id or its name. A name that reads as a number and matches no
-- door is tried as an id, since console input and config strings arrive that way.
local function find(door)
    if type(door) == "number" then return call("getDoor", door) or nil end
    if type(door) ~= "string" or door == "" then return nil end

    local found = call("getDoorFromName", door)

    if not found and tonumber(door) then found = call("getDoor", tonumber(door)) end

    return found or nil
end

gg.doorlock.resource = NAME

-- Doors are read from the database after start; until then every lookup is empty.
gg.doorlock.ready = function()
    if GetResourceState(NAME) ~= "started" then return false end
    if GG_DOORLOCK_LOADED then return true end

    local all = call("getAllDoors")

    return type(all) == "table" and #all > 0
end

gg.doorlock.getDoor = function(door)
    return shape(find(door))
end

-- By its name only: a name that reads as a number is never taken for an id.
gg.doorlock.getDoorByName = function(name)
    if type(name) ~= "string" or name == "" then return nil end

    return shape(call("getDoorFromName", name))
end

gg.doorlock.getDoors = function()
    local out = {}

    for _, door in ipairs(call("getAllDoors") or {}) do
        out[#out + 1] = shape(door)
    end

    return out
end

gg.doorlock.isLocked = function(door)
    local found = find(door)

    if not found then return nil end

    return found.state == 1
end

-- From the server this is unconditional: ox_doorlock checks groups, items and
-- passcodes only for a player's own request.
gg.doorlock.setLocked = function(door, locked)
    local found = find(door)

    if not found then return false end

    return call("setDoorState", found.id, locked and 1 or 0) == true
end

-- state: true / 1 / "locked" locks, anything else unlocks.
gg.doorlock.setState = function(door, state)
    return gg.doorlock.setLocked(door, state == true or state == 1 or state == "locked")
end

-- cb(doorId, locked, source, usedItem). source is nil for the server and for autolock.
gg.doorlock.onChange = function(cb)
    if type(cb) ~= "function" then return false end

    GG_DOORLOCK_LISTENERS[#GG_DOORLOCK_LISTENERS + 1] = cb

    return true
end

--------------------------------------------------
-- MARK: A door's data
--------------------------------------------------

-- ox_doorlock keeps a door as one JSON row (its encodeData): models as signed
-- hashes, coords as { x, y, z }, state 1 locked / 0 unlocked. These turn a door
-- as gg_lib takes it (below, createDoor) into that row and back.

local function round(value, places)
    local scale = 10 ^ (places or 4)

    return math.floor(value * scale + 0.5) / scale
end

local function hashOf(model)
    if type(model) == "string" then
        if model == "" then return nil end

        model = tonumber(model) or (joaat and joaat(model)) or GetHashKey(model)
    end

    if type(model) ~= "number" then return nil end

    model = math.tointeger(model) or math.floor(model)
    model = model & 0xFFFFFFFF

    if model >= 0x80000000 then model = model - 0x100000000 end

    return model
end

local function xyz(value)
    local kind = type(value)

    if kind ~= "table" and kind ~= "vector3" and kind ~= "vector4" then return nil end

    local x = tonumber(value.x) or (kind == "table" and tonumber(value[1])) or nil
    local y = tonumber(value.y) or (kind == "table" and tonumber(value[2])) or nil
    local z = tonumber(value.z) or (kind == "table" and tonumber(value[3])) or nil

    if not x or not y or not z then return nil end

    return { x = round(x), y = round(y), z = round(z) }
end

local function headingOf(value)
    return math.floor((tonumber(value) or 0.0) + 0.5) % 360
end

-- { job = grade } or { "job", ... } (grade 0); nil when there are none.
local function groupsOf(value)
    if type(value) ~= "table" then return nil end

    local out, any = {}, false

    for key, grade in pairs(value) do
        if type(key) == "number" and type(grade) == "string" then key, grade = grade, 0 end

        if type(key) == "string" and key ~= "" then
            out[key] = math.max(0, math.floor(tonumber(grade) or 0))
            any = true
        end
    end

    return any and out or nil
end

local function listOf(value)
    return type(value) == "table" and next(value) ~= nil and value or nil
end

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- The row's data for a door, or nil and why.
local function toData(def)
    if type(def) ~= "table" then return nil, "no door given" end

    local name = text(def.name)

    if not name then return nil, "a door needs a name" end
    if #name > NAME_MAX then return nil, ("the name %s is longer than %d characters"):format(name, NAME_MAX) end

    local data = {}

    if type(def.doors) == "table" then
        if #def.doors ~= 2 then return nil, ("%s: a double door has two leaves"):format(name) end

        data.doors = {}

        for i = 1, 2 do
            local leaf = type(def.doors[i]) == "table" and def.doors[i] or {}
            local model, at = hashOf(leaf.model), xyz(leaf.coords)

            if not model or not at then return nil, ("%s: leaf %d needs a model and coords"):format(name, i) end

            data.doors[i] = { model = model, coords = at, heading = headingOf(leaf.heading) }
        end

        local a, b = data.doors[1].coords, data.doors[2].coords

        data.coords = { x = round((a.x + b.x) / 2), y = round((a.y + b.y) / 2), z = round((a.z + b.z) / 2) }
    else
        local model, at = hashOf(def.model), xyz(def.coords)

        if not model or not at then return nil, ("%s: a door needs a model and coords"):format(name) end

        data.model, data.coords, data.heading = model, at, headingOf(def.heading)
    end

    local autolock = tonumber(def.autolock)

    data.state       = def.locked == false and 0 or 1
    data.groups      = groupsOf(def.groups)
    data.items       = listOf(def.items)
    data.characters  = listOf(def.characters)
    data.maxDistance = tonumber(def.maxDistance) or (data.doors and 2.5 or 2.0)
    data.autolock    = autolock and autolock > 0 and math.floor(autolock) or nil
    data.lockpick    = def.lockpick == true or nil
    data.hideUi      = def.hideUi == true
    data.auto        = def.auto == true or nil
    data.doorRate    = tonumber(def.doorRate)
    data.passcode    = text(def.passcode)
    data.lockSound   = text(def.lockSound)
    data.unlockSound = text(def.unlockSound)
    data.lockpickDifficulty = listOf(def.lockpickDifficulty)

    return data, name
end

-- A row's data as gg_lib hands it out: the same keys createDoor takes.
local function fromData(id, name, data, live)
    data = type(data) == "table" and data or {}

    local out = {
        id          = id,
        name        = name,
        live        = live == true,
        locked      = data.state ~= 0,
        coords      = xyz(data.coords),
        groups      = groupsOf(data.groups),
        items       = listOf(data.items),
        characters  = listOf(data.characters),
        maxDistance = tonumber(data.maxDistance),
        autolock    = tonumber(data.autolock),
        lockpick    = data.lockpick == true,
        hideUi      = data.hideUi == true,
        auto        = data.auto == true,
        doorRate    = tonumber(data.doorRate),
        passcode    = text(data.passcode),
        lockSound   = text(data.lockSound),
        unlockSound = text(data.unlockSound),
    }

    if type(data.doors) == "table" and #data.doors == 2 then
        out.doors = {}

        for i = 1, 2 do
            local leaf = data.doors[i]

            out.doors[i] = { model = hashOf(leaf.model), coords = xyz(leaf.coords), heading = tonumber(leaf.heading) }
        end
    else
        out.model, out.heading = hashOf(data.model), tonumber(data.heading)
    end

    return out
end

--------------------------------------------------
-- MARK: Saved doors
--------------------------------------------------

-- ox_doorlock 1.21 has no export that makes a door: its own /doorlock menu
-- writes a row to its table and adds it to the doors it holds, and only an
-- admin's menu may. So a door made here is written to the same table, the way
-- the menu writes it, and ox_doorlock holds it from its next start (loadSaved
-- below starts it again when nobody is on the server). That needs MySQL in the
-- resource that asks (@oxmysql/lib/MySQL.lua in its server_scripts).

local function db()
    if type(MySQL) ~= "table" or GetResourceState("oxmysql") ~= "started" then return nil end

    return MySQL
end

local function decode(raw)
    local ok, value = pcall(json.decode, raw or "")

    return ok and type(value) == "table" and value or nil
end

local function liveIds()
    local ids = {}

    for _, door in ipairs(call("getAllDoors") or {}) do
        if door.id ~= nil then ids[door.id] = true end
    end

    return ids
end

-- The rows: one by id or name, else every one. Each { id, name, data }.
local function rows(door)
    local sql = db()

    if not sql then return nil end

    local query, args = "SELECT `id`, `name`, `data` FROM `ox_doorlock`", {}

    if type(door) == "number" then
        query, args = query .. " WHERE `id` = ?", { door }
    elseif type(door) == "string" then
        query, args = query .. " WHERE `name` = ?", { door }
    end

    local ok, result = pcall(sql.query.await, query, args)

    if not ok or type(result) ~= "table" then return nil end

    local out = {}

    for _, row in ipairs(result) do
        out[#out + 1] = { id = row.id, name = row.name, data = decode(row.data) or {} }
    end

    return out
end

--- A door as ox_doorlock saved it (id or name), with live = whether ox_doorlock
--- holds it now; with no door, every saved door. nil / {} when the table cannot be read.
gg.doorlock.saved = function(door)
    local found = rows(door)

    if door == nil then
        local out, ids = {}, liveIds()

        for _, row in ipairs(found or {}) do out[#out + 1] = fromData(row.id, row.name, row.data, ids[row.id]) end

        return out
    end

    local row = found and found[1]

    if not row then return nil end

    return fromData(row.id, row.name, row.data, call("getDoor", row.id) ~= nil)
end

--- A door as saved() hands it back once createDoor(def) has made it, or nil and
--- why. Nothing is written: it puts a door through the same rounding, so a
--- script can tell whether a saved door still is what it asked for.
gg.doorlock.shapeOf = function(def)
    local data, name = toData(def)

    if not data then return nil, name end

    return fromData(nil, name, data, false)
end

-- Rows written by this resource since ox_doorlock last started.
GG_DOORLOCK_WAITING = GG_DOORLOCK_WAITING or 0

local function near(a, b)
    if not a or not b then return false end

    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z

    return dx * dx + dy * dy + dz * dz <= NEAR * NEAR
end

--- What this ox_doorlock can do: create = "live" (an export makes doors at once),
--- "saved" (written to its table, held from its next start) or nil (neither).
gg.doorlock.features = function()
    local create = nil

    if has("createDoor") then
        create = "live"
    elseif db() then
        create = "saved"
    end

    return { create = create, edit = has("editDoor"), reload = true }
end

--- Makes a door. def: name (unique, up to 50 characters); model, coords, heading,
--- or doors = { { model, coords, heading }, { ... } } for a double door; locked
--- (default true); groups ({ job = grade }); and optionally items, characters,
--- maxDistance, autolock (seconds), lockpick, hideUi, auto, doorRate, passcode,
--- lockSound, unlockSound. Returns id, "live" | "saved", or false, why[, id of
--- the door already there]. A name already saved is never made twice.
gg.doorlock.createDoor = function(def)
    if GetResourceState(NAME) ~= "started" then return false, ("%s is not started"):format(NAME) end

    local data, name = toData(def)

    if not data then return false, name end

    local live = call("getDoorFromName", name)

    if live then return false, "exists", live.id end

    local saved = rows(name)

    if saved and saved[1] then return false, "exists", saved[1].id end

    -- A newer ox_doorlock with an export of its own: made at once, then found by name or where it stands.
    if has("createDoor") then
        local payload = {}

        for key, value in pairs(data) do payload[key] = value end

        payload.name = name

        pcall(invoke, "createDoor", payload)

        local made = call("getDoorFromName", name)

        if not made then
            for _, door in ipairs(call("getAllDoors") or {}) do
                if near(xyz(door.coords), data.coords) then made = door break end
            end
        end

        if made then return made.id, "live" end
    end

    local sql = db()

    if not sql then
        return false, ("%s cannot reach the database (add @oxmysql/lib/MySQL.lua to its server_scripts)"):format(GetCurrentResourceName())
    end

    local ok, id = pcall(sql.insert.await, "INSERT INTO `ox_doorlock` (`name`, `data`) VALUES (?, ?)", { name, json.encode(data) })

    if not ok or not id then return false, ("the database refused it: %s"):format(tostring(id)) end

    GG_DOORLOCK_WAITING = GG_DOORLOCK_WAITING + 1

    return id, "saved"
end

-- What editDoor may change on a door ox_doorlock holds now, by ox_doorlock's own key.
local LIVE_KEYS = {
    "state", "groups", "items", "characters", "maxDistance", "autolock", "lockpick", "hideUi", "auto", "doorRate",
    "passcode", "lockSound", "unlockSound",
}

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end

    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end

    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

-- ox_doorlock writes a row back from the door it holds, whose coords are floats
-- (-1279.7894 comes back as -1279.789429...), so a place counts as the same to 1 cm.
local function near(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return a == b end

    return math.abs(a - b) <= 0.01
end

local function sameSpot(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end

    return near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z)
end

local function sameLeaf(a, b)
    return a.model == b.model and near(a.heading, b.heading) and sameSpot(a.coords, b.coords)
end

local function sameGeometry(a, b)
    if (a.doors == nil) ~= (b.doors == nil) then return false end

    if a.doors then return sameLeaf(a.doors[1], b.doors[1]) and sameLeaf(a.doors[2], b.doors[2]) end

    return sameLeaf(a, b)
end

--- Changes a door (id or name): any key createDoor takes, a key set to false
--- clears it (groups = false: nobody's job opens it). A door ox_doorlock holds
--- takes it at once; its model or place, or a door it does not hold yet, is
--- changed in its saved row and taken at its next start. Returns true, "live" |
--- "saved", or false, why.
gg.doorlock.editDoor = function(door, changes)
    if GetResourceState(NAME) ~= "started" then return false, ("%s is not started"):format(NAME) end
    if type(changes) ~= "table" then return false, "nothing to change" end

    local live = find(door)
    local found = rows(live and live.id or door)
    local row = found and found[1]

    if not row then return false, live and "its saved row cannot be read" or "no such door" end

    local def = fromData(row.id, row.name, row.data)

    def.name = row.name

    -- The row as it stands, put through the same rounding, so only a real change counts.
    local was = toData(def)

    for key, value in pairs(changes) do
        if value == false and key ~= "locked" and key ~= "lockpick" and key ~= "hideUi" and key ~= "auto" then value = nil end

        def[key] = value
    end

    -- A double door given a single leaf (or the other way round) drops the old shape.
    if changes.doors then def.model, def.heading = nil, nil elseif changes.model then def.doors = nil end

    local data, why = toData(def)

    if not data then return false, why end

    local moved = not was or not sameGeometry(data, was)

    if live and not moved then
        local diff = {}

        -- Every key asked for (the state too: a door in use may stand other than saved), and any that differs from
        -- the saved row. "" is ox_doorlock's own way to clear one.
        for _, key in ipairs(LIVE_KEYS) do
            local asked = changes[key == "state" and "locked" or key] ~= nil

            if asked or not same(data[key], was[key]) then diff[key] = data[key] == nil and "" or data[key] end
        end

        if def.name ~= row.name then diff.name = def.name end

        if next(diff) == nil then return true, "live" end

        local ok, err = pcall(invoke, "editDoor", live.id, diff)

        if ok then return true, "live" end

        return false, tostring(err)
    end

    local sql = db()

    if not sql then return false, ("%s cannot reach the database"):format(GetCurrentResourceName()) end

    local ok, err = pcall(sql.update.await, "UPDATE `ox_doorlock` SET `name` = ?, `data` = ? WHERE `id` = ?", { def.name, json.encode(data), row.id })

    if not ok then return false, tostring(err) end

    GG_DOORLOCK_WAITING = GG_DOORLOCK_WAITING + 1

    return true, "saved"
end

-- A started resource that names ox_doorlock as a dependency: stopping ox_doorlock would stop it too.
local function dependent()
    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)

        if resource and resource ~= NAME and GetResourceState(resource) == "started" then
            for _, key in ipairs({ "dependency", "dependencies" }) do
                for i = 0, (GetNumResourceMetadata(resource, key) or 0) - 1 do
                    if GetResourceMetadata(resource, key, i) == NAME then return resource end
                end
            end
        end
    end

    return nil
end

--- Has ox_doorlock read the rows this resource saved (createDoor / editDoor
--- "saved") by starting it again, only while nobody is on the server and no
--- started resource depends on it. Returns true, why, or false, why: then the
--- rows are taken at its next start (the next server restart).
gg.doorlock.loadSaved = function()
    if GetResourceState(NAME) ~= "started" then return false, ("%s is not started"):format(NAME) end
    if GG_DOORLOCK_WAITING == 0 then return true, "nothing waiting" end

    local players = GetNumPlayerIndices()

    if players > 0 then return false, ("%d player(s) on the server"):format(players) end

    local needs = dependent()

    if needs then return false, ("%s depends on %s"):format(needs, NAME) end

    local waiting = GG_DOORLOCK_WAITING

    GG_DOORLOCK_WAITING = 0
    GG_DOORLOCK_LOADED = false

    -- Refused (the server may not let a script stop another): it still runs without the rows, so they keep waiting.
    if StopResource(NAME) == false and GetResourceState(NAME) == "started" then
        GG_DOORLOCK_WAITING = waiting
        GG_DOORLOCK_LOADED = true

        return false, ("%s could not be stopped from %s"):format(NAME, GetCurrentResourceName())
    end

    if not StartResource(NAME) and GetResourceState(NAME) ~= "started" and GetResourceState(NAME) ~= "starting" then
        return false, ("%s did not start again: start it by hand"):format(NAME)
    end

    return true, ("%s started again"):format(NAME)
end

--------------------------------------------------
-- MARK: Events
--------------------------------------------------

if not GG_DOORLOCK_EVENTS then
    GG_DOORLOCK_EVENTS = true

    -- It has just read every row, ours too, however it was started again.
    AddEventHandler("ox_doorlock:loaded", function()
        GG_DOORLOCK_LOADED = true
        GG_DOORLOCK_WAITING = 0
    end)

    AddEventHandler("onResourceStop", function(stopped)
        if stopped == NAME then GG_DOORLOCK_LOADED = false end
    end)

    AddEventHandler("ox_doorlock:stateChanged", function(player, doorId, locked, usedItem)
        player = type(player) == "number" and player > 0 and player or nil

        for _, cb in ipairs(GG_DOORLOCK_LISTENERS) do
            local ok, err = pcall(cb, doorId, locked == true, player, usedItem or nil)

            if not ok then gg.print.warn(("doorlock listener failed: %s"):format(tostring(err))) end
        end
    end)
end

-- The client looks doors up here. It gets no access lists back, and only reads.
if not GG_DOORLOCK_CALLBACK then
    GG_DOORLOCK_CALLBACK = true

    gg.callback.register(GetCurrentResourceName() .. ":doorlock:door", function(_, door)
        local found = gg.doorlock.getDoor(door)

        if not found then return nil end

        return {
            id          = found.id,
            name        = found.name,
            locked      = found.locked,
            coords      = found.coords,
            maxDistance = found.maxDistance,
        }
    end)
end

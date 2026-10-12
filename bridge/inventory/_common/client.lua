-- Runs after every inventory bridge (and the fallback) installs, on the client.
-- Same rows as the server: { name, label, count, slot, metadata, weight }.
gg.inventory = gg.inventory or {}

local inventory = gg.inventory
local native = {}

for name, fn in pairs(inventory) do
    if type(fn) == "function" then native[name] = fn end
end

local function same(a, b)
    if a == b then return true end
    if type(a) == "number" or type(b) == "number" then return tonumber(a) ~= nil and tonumber(a) == tonumber(b) end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end

    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

local function matches(metadata, wanted)
    if type(wanted) ~= "table" or next(wanted) == nil then return true end
    if type(metadata) ~= "table" then return false end

    for key, value in pairs(wanted) do
        if not same(metadata[key], value) then return false end
    end

    return true
end

local function row(item, slot)
    if type(item) ~= "table" or type(item.name) ~= "string" then return nil end

    local metadata = item.metadata

    if type(metadata) ~= "table" then metadata = item.info end
    if type(metadata) ~= "table" then metadata = {} end

    return {
        name     = item.name,
        label    = item.label,
        count    = tonumber(item.count or item.amount) or 1,
        slot     = tonumber(item.slot) or item.slot or tonumber(slot) or slot,
        metadata = metadata,
        weight   = tonumber(item.weight),
    }
end

inventory.row     = row
inventory.matches = matches

local function call(fn, ...)
    if not fn then return false end

    local ok, result = pcall(fn, ...)

    if not ok then
        print(("^1[gg_lib] inventory %s: %s^0"):format(tostring(gg.bridge and gg.bridge.inventory), tostring(result)))
        return false
    end

    return true, result
end

local function itemOf(item, metadata)
    if type(item) == "table" then return item.item or item.name, item.metadata end
    return item, metadata
end

--- Every item this player carries, sorted by slot.
inventory.getItems = function()
    local ok, items = call(native.getItems)
    local list = {}

    if not ok or type(items) ~= "table" then return list end

    for slot, item in pairs(items) do
        local value = row(item, slot)

        if value and value.count > 0 then list[#list + 1] = value end
    end

    table.sort(list, function(a, b)
        local x, y = tonumber(a.slot), tonumber(b.slot)

        if x and y then return x < y end

        return tostring(a.slot) < tostring(b.slot)
    end)

    return list
end

--- How many of an item this player carries, counting only stacks whose
--- metadata holds every key given.
inventory.getCount = function(item, metadata)
    item, metadata = itemOf(item, metadata)

    if type(item) ~= "string" then return 0 end

    local filtered = type(metadata) == "table" and next(metadata) ~= nil

    if native.getCount then
        local ok, count = call(native.getCount, item, filtered and metadata or nil)

        if ok and tonumber(count) then return tonumber(count) end
    end

    local total = 0

    for _, value in ipairs(inventory.getItems()) do
        if value.name == item and matches(value.metadata, metadata) then total = total + value.count end
    end

    return total
end

inventory.hasItem = function(item, count, metadata)
    local name, wanted = itemOf(item, metadata)

    if type(item) == "table" then count = item.count end

    return inventory.getCount(name, wanted) >= (tonumber(count) or 1)
end

-- A bridge that failed half way still answers the catalogue calls.
for _, name in ipairs({ "getItemTable", "getImageUrl", "getImageDirectory" }) do
    if not inventory[name] then inventory[name] = function() return nil end end
end

--- Use an item the player picked. ox_inventory plays its use animation and
--- takes the item first, then runs `cb(data)` once it went through; every
--- other inventory already did that before the script heard of it.
inventory.useItem = function(data, cb)
    if type(cb) ~= "function" then return false end

    if native.useItem then
        local ok = call(native.useItem, data, cb)

        if ok then return true end
    end

    cb(data)

    return true
end

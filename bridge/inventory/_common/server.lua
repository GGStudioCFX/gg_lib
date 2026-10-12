-- Runs after every inventory bridge (and the fallback) installs, in the
-- consuming resource. The bridge defines the inventory's own calls; this file
-- turns them into one API: rows always read { name, label, count, slot,
-- metadata, weight }, metadata is always a table, and what an inventory has no
-- export for is worked out from its item list.
gg.inventory = gg.inventory or {}

local inventory = gg.inventory
local native = {}
local live = gg.bridge ~= nil and gg.bridge.inventory ~= nil and gg.bridge.inventory ~= "default"

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

-- Every key the caller asks for has to be there with the same value; the item
-- may carry more (durability, serials, ...). The same test ox_inventory uses.
local function matches(metadata, wanted)
    if type(wanted) ~= "table" or next(wanted) == nil then return true end
    if type(metadata) ~= "table" then return false end

    for key, value in pairs(wanted) do
        if not same(metadata[key], value) then return false end
    end

    return true
end

local function hasKeys(value)
    return type(value) == "table" and next(value) ~= nil
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

    local ok, result, extra = pcall(fn, ...)

    if not ok then
        print(("^1[gg_lib] inventory %s: %s^0"):format(tostring(gg.bridge and gg.bridge.inventory), tostring(result)))
        return false
    end

    return true, result, extra
end

local function itemOf(item, metadata)
    if type(item) == "table" then return item.item or item.name, item.metadata end
    return item, metadata
end

--- Every item the player carries, sorted by slot.
---@return table[] { name, label, count, slot, metadata, weight }
inventory.getItems = function(src)
    local ok, items = call(native.getItems, src)
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

--- The item in one slot, or nil.
inventory.getSlot = function(src, slot)
    if slot == nil then return nil end

    if native.getSlot then
        local ok, item = call(native.getSlot, src, slot)

        if ok then
            local value = row(item, slot)

            if value and value.count > 0 then return value end
            if item == nil or item == false then return nil end
        end
    end

    for _, item in ipairs(inventory.getItems(src)) do
        if same(item.slot, slot) then return item end
    end

    return nil
end

--- The first stack of an item (with this metadata, when given), or nil.
inventory.findItem = function(src, item, metadata)
    item, metadata = itemOf(item, metadata)

    for _, value in ipairs(inventory.getItems(src)) do
        if value.name == item and matches(value.metadata, metadata) then return value end
    end

    return nil
end

--- How many of an item the player carries, counting only stacks whose metadata
--- holds every key given.
inventory.getCount = function(src, item, metadata)
    item, metadata = itemOf(item, metadata)

    if type(item) ~= "string" then return 0 end

    if native.getCount then
        local ok, count = call(native.getCount, src, item, hasKeys(metadata) and metadata or nil)

        if ok and tonumber(count) then return tonumber(count) end
    end

    local total = 0

    for _, value in ipairs(inventory.getItems(src)) do
        if value.name == item and matches(value.metadata, metadata) then total = total + value.count end
    end

    return total
end

inventory.hasItem = function(src, data)
    if type(data) ~= "table" then return false end

    local count = tonumber(data.count) or 1

    if hasKeys(data.metadata) or not native.hasItem then
        if inventory.getCount(src, data.item, data.metadata) >= count then return true end

        return false, { err = "You do not have enough of this item" }
    end

    data.count = count

    local ok, has, why = call(native.hasItem, src, data)

    if not ok then return false end

    return has and true or false, why
end

--- Replace the metadata of the item in a slot. True once the inventory took it.
inventory.setMetadata = function(src, slot, metadata)
    if slot == nil or type(metadata) ~= "table" then return false end
    if not native.setMetadata then return false end

    local ok, result = call(native.setMetadata, src, slot, metadata)

    return ok and result ~= false
end

inventory.canCarryitem = function(src, data)
    if type(data) ~= "table" then return false end
    if not native.canCarryitem then return false end

    local ok, can, why = call(native.canCarryitem, src, data)

    if not ok then return false end

    return can and true or false, why
end

inventory.canCarryWeight = function(src, weight)
    if not native.canCarryWeight then return live end

    local ok, can = call(native.canCarryWeight, src, tonumber(weight) or 0)

    return ok and can ~= false
end

inventory.addItem = function(src, data)
    if type(data) ~= "table" or type(data.item) ~= "string" then return false end
    if not native.addItem then return false end

    data.count = tonumber(data.count) or 1

    local ok, added, why = call(native.addItem, src, data)

    if not ok then return false end

    return added and true or false, why
end

-- An inventory whose remove export only knows a slot gets the slot of the
-- matching stack, so metadata always picks the right item.
inventory.removeItem = function(src, data)
    if type(data) ~= "table" or type(data.item) ~= "string" then return false end
    if not native.removeItem then return false end

    data.count = tonumber(data.count) or 1

    if data.slot == nil and hasKeys(data.metadata) then
        local stack = inventory.findItem(src, data.item, data.metadata)

        if not stack then return false, { err = "You do not have enough of this item" } end
        if stack.count >= data.count then data.slot = stack.slot end
    end

    local ok, removed, why = call(native.removeItem, src, data)

    if not ok then return false end

    return removed and true or false, why
end

-- The framework's usable items hand over (src, item) on QBCore and Qbox, and
-- (src, name, item) on ESX. The callback always gets one row.
local function usableRow(name, a, b)
    return row(type(a) == "table" and a or type(b) == "table" and b or nil) or { name = name, count = 1, metadata = {} }
end

--- Run `cb(src, row)` when a player uses the item. Uses the inventory's own
--- usable items where it has them, the framework's otherwise. ox_inventory
--- also runs the client export named on the item, as before.
inventory.registerUsable = function(item, cb)
    if type(item) ~= "string" or type(cb) ~= "function" then return false end

    local handler = function(src, a, b) cb(src, usableRow(item, a, b)) end

    if native.registerUsable then
        local ok, result = call(native.registerUsable, item, handler)

        if ok and result ~= false then return true end
    end

    if gg.framework and gg.framework.RegisterUsableItem then
        local ok = call(gg.framework.RegisterUsableItem, item, handler)

        return ok
    end

    return false
end

--- Watch items moving between slots and inventories. `cb(payload)` returning
--- false stops the move. Only ox_inventory has this; elsewhere it returns nil.
inventory.onSwap = function(cb, options)
    if type(cb) ~= "function" or not native.onSwap then return nil end

    local ok, id = call(native.onSwap, cb, options)

    return ok and id or nil
end

inventory.removeHook = function(id)
    if id == nil or not native.removeHook then return false end

    return (call(native.removeHook, id))
end

-- A bridge that failed half way still answers the catalogue calls.
for _, name in ipairs({ "getItemTable", "getImageUrl" }) do
    if not inventory[name] then inventory[name] = function() return nil end end
end

--- Whether this inventory can keep metadata on an item. Every bridge can; the
--- fallback can't.
inventory.hasMetadata = function()
    return live and native.setMetadata ~= nil and native.getItems ~= nil
end

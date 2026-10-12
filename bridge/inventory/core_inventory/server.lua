gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports.core_inventory:canCarry(src, data.item, data.count or 1, data.metadata or nil)
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports.core_inventory:addItem(src, data.item, data.count, data.metadata)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local exact = data.slot ~= nil and exports.core_inventory:getItemBySlot(src, data.slot) or nil
    local result

    if type(exact) == "table" and exact.id and exact.name == data.item then
        result = exports.core_inventory:removeItemExact(src, exact.id, data.count)
    else
        result = exports.core_inventory:removeItem(src, data.item, data.count)
    end

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-core_inventory/html/img/%s.png', item)
end

-- getInventory().content is keyed by slot; rows read amount / metadata.
local function contentRows(inventory)
    local content = type(inventory) == "table" and (inventory.content or inventory.items or inventory) or {}
    local list = {}

    for key, item in pairs(content) do
        if type(item) == "table" and item.name then
            item.slot = item.slot or tonumber(key) or key
            list[#list + 1] = item
        end
    end

    return list
end

gg.inventory.getItems = function(src)
    return contentRows(exports.core_inventory:getInventory(src))
end

gg.inventory.getSlot = function(src, slot)
    return exports.core_inventory:getItemBySlot(src, slot)
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports.core_inventory:getItemCount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not exports.core_inventory:getItemBySlot(src, slot) then return false end

    exports.core_inventory:setMetadata(src, slot, metadata)

    return true
end

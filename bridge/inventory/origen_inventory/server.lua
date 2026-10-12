gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports.origen_inventory:canCarryItem(src, data.item, data.count, data.metadata)
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports.origen_inventory:addItem(src, data.item, data.count, data.metadata, data.slot, false)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports.origen_inventory:removeItem(src, data.item, data.count, data.metadata, data.slot, false)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-origen_inventory/html/images/%s.png', item)
end

-- Rows read amount / info.
gg.inventory.getItems = function(src)
    local ok, items = pcall(function() return exports.origen_inventory:getInventory(src) end)
    if ok and type(items) == "table" then return items.items or items end

    return exports.origen_inventory:getItems(src)
end

gg.inventory.getSlot = function(src, slot)
    return exports.origen_inventory:getSlot(src, slot)
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports.origen_inventory:getItemCount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not gg.inventory.getSlot(src, slot) then return false end

    exports.origen_inventory:setMetadata(src, slot, metadata)

    return true
end

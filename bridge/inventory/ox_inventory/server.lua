gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports.ox_inventory:CanCarryItem(src, data.item, data.count, data.metadata) -- Ox Handles inside base events
end

gg.inventory.canCarryWeight = function(src, weight)
    return exports.ox_inventory:CanCarryWeight(src, weight)
end

gg.inventory.hasItem = function(src, data)
    local item = exports.ox_inventory:GetItem(src, data.item, nil, false)
    return item and item.count >= data.count
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports.ox_inventory:AddItem(src, data.item, data.count, data.metadata, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    -- strict = false: metadata matches the way Search counts it (every key asked for), not the whole table.
    local result = exports.ox_inventory:RemoveItem(src, data.item, data.count, data.metadata, data.slot, true, false)

    if result == false then return false end

    return true
end

gg.inventory.getItems = function(src)
    return exports.ox_inventory:GetInventoryItems(src)
end

gg.inventory.getSlot = function(src, slot)
    return exports.ox_inventory:GetSlot(src, slot)
end

-- Search matches metadata the way the rest of gg.inventory does: every key
-- asked for has to be there, the item may carry more.
gg.inventory.getCount = function(src, item, metadata)
    return exports.ox_inventory:Search(src, 'count', item, metadata)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not exports.ox_inventory:GetSlot(src, slot) then return false end

    exports.ox_inventory:SetMetadata(src, slot, metadata)

    return true
end

gg.inventory.onSwap = function(cb, options)
    return exports.ox_inventory:registerHook('swapItems', cb, options)
end

gg.inventory.removeHook = function(id)
    exports.ox_inventory:removeHooks(id)

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return exports.ox_inventory:Items() end
    return exports.ox_inventory:Items(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-ox_inventory/web/images/%s.png', item)
end

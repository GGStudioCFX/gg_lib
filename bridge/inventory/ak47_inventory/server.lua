gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports['ak47_inventory']:CanAddItem(src, data.item, data.count)
end

gg.inventory.hasItem = function(src, data)
    local item = exports['ak47_inventory']:GetItem(src, data.item, nil, false)
    return item and item.count >= data.count
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports['ak47_inventory']:AddItem(src, data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports['ak47_inventory']:RemoveItem(src, data.item, data.count, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return exports['ak47_inventory']:Items() end
    return exports['ak47_inventory']:Items(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-ak47_inventory/web/images/%s.png', item)
end

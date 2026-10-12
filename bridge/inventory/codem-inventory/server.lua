gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return true
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports['codem-inventory']:AddItem(src, data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports['codem-inventory']:RemoveItem(src, data.item, data.count, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    local payload = exports['codem-inventory']:GetItemList()
    if not item then return payload end
    return payload[item] or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-codem-inventory/html/itemimages/%s.png', item)
end

-- codem keys a player's inventory by their citizenid / ESX identifier.
gg.inventory.getItems = function(src)
    local identifier = gg.framework.GetIdentifier and gg.framework.GetIdentifier(src)

    return exports['codem-inventory']:GetInventory(identifier, src)
end

gg.inventory.getSlot = function(src, slot)
    return exports['codem-inventory']:GetItemBySlot(src, slot)
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports['codem-inventory']:GetItemsTotalAmount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not exports['codem-inventory']:GetItemBySlot(src, slot) then return false end

    exports['codem-inventory']:SetItemMetadata(src, slot, metadata)

    return true
end

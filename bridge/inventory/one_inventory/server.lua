gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports.one_inventory:CanCarryItem(src, data.item, data.count, data.metadata) -- Ox Handles inside base events
end

gg.inventory.hasItem = function(src, data)
    local item = exports.one_inventory:GetItem(src, data.item, nil, false)
    return item and item.count >= data.count
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports.one_inventory:AddItem(src, data.item, data.count, data.metadata, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports.one_inventory:RemoveItem(src, data.item, data.count, data.metadata, data.slot, true)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return exports.one_inventory:GetAllItemDefinitions() end
    return exports.one_inventory:GetItemDefinition(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-one_inventory/web/images/%s.png', item)
end

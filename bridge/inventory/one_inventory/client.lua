gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-one_inventory/web/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-one_inventory/web/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports.one_inventory:GetAllItemDefinitions() end
    return exports.one_inventory:GetItemDefinition(item) or nil
end

gg.inventory.getItems = function()
    return exports.one_inventory:GetInventoryItems()
end

gg.inventory.getCount = function(item, metadata)
    if metadata then return nil end

    return exports.one_inventory:GetItemCount(item)
end

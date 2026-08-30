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

gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-ox_inventory/web/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-ox_inventory/web/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports.ox_inventory:Items() end
    return exports.ox_inventory:Items(item) or nil
end

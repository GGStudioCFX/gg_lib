gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-ak47_inventory/web/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-ak47_inventory/web/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports['ak47_inventory']:Items() end
    return exports['ak47_inventory']:Items(item) or nil
end

gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-inventory_images/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-inventory_images/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports["tgiann-inventory"]:Items() end
    return exports["tgiann-inventory"]:Items(item) or nil
end

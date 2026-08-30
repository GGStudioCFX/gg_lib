gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-qb-inventory/html/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-qb-inventory/html/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

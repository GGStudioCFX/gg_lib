gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-core_inventory/html/img/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-core_inventory/html/img/'
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

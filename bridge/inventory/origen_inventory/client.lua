gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-origen_inventory/html/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-origen_inventory/html/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

gg.inventory.getItems = function()
    local ok, items = pcall(function() return exports.origen_inventory:getPlayerItems() end)
    if ok and type(items) == "table" then return items end

    return exports.origen_inventory:GetInventory()
end

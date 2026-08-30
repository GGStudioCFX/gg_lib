gg.inventory = gg.inventory or {}

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-codem-inventory/html/itemimages/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-codem-inventory/html/itemimages/'
end

gg.inventory.getItemTable = function(item)
    local payload = exports['codem-inventory']:GetItemList()
    if not item then return payload end
    return payload[item] or nil
end

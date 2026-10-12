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

gg.inventory.getItems = function()
    return exports.ox_inventory:GetPlayerItems()
end

gg.inventory.getCount = function(item, metadata)
    return exports.ox_inventory:Search('count', item, metadata)
end

-- The item's client export runs first; useItem plays the animation, takes the
-- item and calls back once it went through.
gg.inventory.useItem = function(data, cb)
    exports.ox_inventory:useItem(data, cb)
end

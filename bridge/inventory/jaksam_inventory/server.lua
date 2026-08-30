gg.inventory = gg.inventory or {}

local function toNuiUrl(path)
    if type(path) ~= "string" or path == "" then return nil end

    return (path:gsub("^nui://", "https://cfx-nui-"))
end

gg.inventory.canCarryitem = function(src, data)
    return exports['jaksam_inventory']:canCarryItem(src, data.item, data.count or 1)
end

gg.inventory.hasItem = function(src, data)
    return exports['jaksam_inventory']:hasItem(src, data.item, data.count or 1)
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports['jaksam_inventory']:addItem(src, data.item, data.count, data.metadata, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports['jaksam_inventory']:removeItem(src, data.item, data.count, data.metadata, data.slot)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return exports['jaksam_inventory']:getStaticItemsList() end

    return exports['jaksam_inventory']:getStaticItem(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return toNuiUrl(exports['jaksam_inventory']:getItemImagePath(item))
end

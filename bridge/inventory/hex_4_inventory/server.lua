gg.inventory = gg.inventory or {}

-- HEX Inventory v4 draws ESX's own player inventory: it reads xPlayer.getInventory()
-- and writes through addInventoryItem, and its exports only cover stashes, trunks
-- and hooks. So player items go through xPlayer here, the way PiotreeQ's p_bridge
-- and Oxide's o-link bridge it. ESX's item store has no metadata.
local ESX = exports.es_extended:getSharedObject()

local function player(src)
    return ESX.GetPlayerFromId(src)
end

gg.inventory.canCarryitem = function(src, data)
    local xPlayer = player(src)

    if not xPlayer or not xPlayer.getInventoryItem(data.item) then return false end
    if not xPlayer.canCarryItem then return true end

    return xPlayer.canCarryItem(data.item, data.count or 1) == true
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    player(src).addInventoryItem(data.item, data.count)

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    player(src).removeInventoryItem(data.item, data.count)

    return true
end

gg.inventory.getItems = function(src)
    local xPlayer = player(src)

    if not xPlayer then return {} end

    return xPlayer.getInventory()
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    local xPlayer = player(src)
    local row = xPlayer and xPlayer.getInventoryItem(item)

    return row and row.count or 0
end

gg.inventory.getItemTable = function(item)
    local items = type(ESX.Items) == "table" and ESX.Items or {}

    if not item then return items end

    local data = items[item]

    if type(data) == "table" then data.name = data.name or item end

    return data
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-hex_4_inventory/dist/img/icons/%s.png', item)
end

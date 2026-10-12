gg.inventory = gg.inventory or {}

local core

-- A qb-inventory fork: the player's items live in PlayerData.items (amount, info).
local function player(src)
    if GetResourceState('qbx_core') == 'started' then
        local ok, value = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and value then return value end
    end

    if GetResourceState('qb-core') == 'started' then
        core = core or exports['qb-core']:GetCoreObject()
        return core and core.Functions.GetPlayer(src) or nil
    end
end

gg.inventory.canCarryitem = function(src, data)
    local ok, can = pcall(function() return exports['ps-inventory']:CanAddItem(src, data.item, data.count or 1) end)
    if ok and can ~= nil then return can == true end
    return true
end

gg.inventory.hasItem = function(src, data)
    local inventory = gg.framework.GetInventory(src)
    if not inventory then
        return false, {err = "Failed to get inventory"}
    end
    local count = 0
    for k,v in pairs(inventory) do
        if v.name == data.item then
            count = count + v.count
        end
    end

    if count < data.count then
        return false, {err = "You do not have enough of this item"}
    end

    return true
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports['ps-inventory']:AddItem(src, data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    TriggerClientEvent('ps-inventory:client:ItemBox', src, gg.framework.getItemTable(data.item), 'add', data.count)

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports['ps-inventory']:RemoveItem(src, data.item, data.count, data.slot, data.reason)

    if result == false then return false end

    TriggerClientEvent('ps-inventory:client:ItemBox', src, gg.framework.getItemTable(data.item), 'remove', data.count)

    return true
end

gg.inventory.getItems = function(src)
    local value = player(src)
    return value and value.PlayerData and value.PlayerData.items or {}
end

-- The same write the inventory's own SetItemData makes, aimed at one slot.
gg.inventory.setMetadata = function(src, slot, metadata)
    local value = player(src)
    local items = value and value.PlayerData and value.PlayerData.items
    if type(items) ~= 'table' then return false end

    for key, item in pairs(items) do
        if type(item) == 'table' and (tonumber(item.slot) or tonumber(key)) == tonumber(slot) then
            item.info = metadata
            value.Functions.SetPlayerData('items', items)
            return true
        end
    end

    return false
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-ps-inventory/html/images/%s.png', item)
end

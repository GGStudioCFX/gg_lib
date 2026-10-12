gg.inventory = gg.inventory or {}

local core

local function playerItems()
    if GetResourceState('qbx_core') == 'started' then
        local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
        if ok and data then return data.items end
    end

    if GetResourceState('qb-core') == 'started' then
        core = core or exports['qb-core']:GetCoreObject()
        local data = core and core.Functions.GetPlayerData()
        return data and data.items
    end
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-jpr-inventory/html/images/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-jpr-inventory/html/images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return gg.framework.getItemTable() end
    return gg.framework.getItemTable(item) or nil
end

gg.inventory.getItems = function()
    return playerItems() or {}
end

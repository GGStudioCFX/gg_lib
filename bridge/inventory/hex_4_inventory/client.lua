gg.inventory = gg.inventory or {}

-- HEX Inventory v4 shows ESX's own player inventory, so the rows and item labels
-- come from ESX's player data (see server.lua).
local ESX = exports.es_extended:getSharedObject()

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-hex_4_inventory/dist/img/icons/%s.png', item)
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-hex_4_inventory/dist/img/icons/'
end

gg.inventory.getItems = function()
    return ESX.GetPlayerData().inventory or {}
end

gg.inventory.getItemTable = function(item)
    local items = {}

    for _, row in pairs(ESX.GetPlayerData().inventory or {}) do
        if type(row) == "table" and row.name then
            items[row.name] = { name = row.name, label = row.label, weight = row.weight }
        end
    end

    if not item then return items end

    return items[item]
end

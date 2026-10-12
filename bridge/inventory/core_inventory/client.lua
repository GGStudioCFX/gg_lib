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

-- getInventory().content is keyed by slot; rows read amount / metadata.
local function contentRows(inventory)
    local content = type(inventory) == "table" and (inventory.content or inventory.items or inventory) or {}
    local list = {}

    for key, item in pairs(content) do
        if type(item) == "table" and item.name then
            item.slot = item.slot or tonumber(key) or key
            list[#list + 1] = item
        end
    end

    return list
end

gg.inventory.getItems = function()
    return contentRows(exports.core_inventory:getInventory())
end

gg.inventory.getCount = function(item, metadata)
    if metadata then return nil end

    return exports.core_inventory:getItemCount(item)
end

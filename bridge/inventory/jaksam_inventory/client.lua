gg.inventory = gg.inventory or {}

local function toNuiUrl(path)
    if type(path) ~= "string" or path == "" then return nil end

    return (path:gsub("^nui://", "https://cfx-nui-"))
end

gg.inventory.getImageUrl = function(item)
    return toNuiUrl(exports['jaksam_inventory']:getItemImagePath(item))
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-jaksam_inventory/_images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports['jaksam_inventory']:getStaticItemsList() end

    return exports['jaksam_inventory']:getStaticItem(item) or nil
end

-- getInventory().items is keyed "SLOT-4"; the number is the slot.
local function slotRows(inventory)
    local list = {}
    local items = type(inventory) == "table" and inventory.items or {}

    for key, item in pairs(type(items) == "table" and items or {}) do
        if type(item) == "table" then
            item.slot = item.slot or tonumber(tostring(key):match("(%d+)$"))
            list[#list + 1] = item
        end
    end

    return list
end

gg.inventory.getItems = function()
    return slotRows(exports['jaksam_inventory']:getInventory())
end

gg.inventory.getCount = function(item, metadata)
    if metadata then return nil end

    return exports['jaksam_inventory']:getTotalItemAmount(item)
end

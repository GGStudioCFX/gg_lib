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

gg.inventory.getItems = function(src)
    return slotRows(exports['jaksam_inventory']:getInventory(src))
end

gg.inventory.getSlot = function(src, slot)
    return exports['jaksam_inventory']:getItemFromSlot(src, slot)
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports['jaksam_inventory']:getTotalItemAmount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    return exports['jaksam_inventory']:setItemMetadataInSlot(src, slot, metadata) ~= false
end

-- jaksam runs its own usable items on ESX and QBCore alike.
gg.inventory.registerUsable = function(item, cb)
    exports['jaksam_inventory']:registerUsableItem(item, cb)

    return true
end

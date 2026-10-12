gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    local canCarry = exports['qs-inventory']:CanCarryItem(src, data.item, data.count)
    if not canCarry then
        return false, {err = "You cannot carry this item"}
    end
    return canCarry
end

gg.inventory.hasItem = function(src, data)
    local required = data.count or 1
    local count = 0

    local ok, result = pcall(function()
        return exports['qs-inventory']:GetItemTotalAmount(src, data.item)
    end)

    if ok and type(result) == "number" then
        count = result
    else
        local inventory = exports['qs-inventory']:GetInventory(src)
        if not inventory then
            return false, {err = "Failed to get inventory"}
        end
        for _, v in pairs(inventory) do
            if v and v.name == data.item then
                count = count + (v.amount or v.count or 0)
            end
        end
    end

    if count < required then
        return false, {err = "You do not have enough of this item"}
    end

    return true
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports['qs-inventory']:AddItem(src,  data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports['qs-inventory']:RemoveItem(src, data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    return true
end

-- Slot-keyed rows of { name, label, amount, info, slot, weight }.
gg.inventory.getItems = function(src)
    return exports['qs-inventory']:GetInventory(src)
end

-- Without metadata qs counts it itself; with metadata gg.inventory reads the rows.
gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports['qs-inventory']:GetItemTotalAmount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    local items = exports['qs-inventory']:GetInventory(src)
    local item = type(items) == "table" and (items[slot] or items[tostring(slot)])

    if type(item) ~= "table" then
        for _, value in pairs(type(items) == "table" and items or {}) do
            if type(value) == "table" and tonumber(value.slot) == tonumber(slot) then item = value break end
        end
    end

    if type(item) ~= "table" then return false end

    exports['qs-inventory']:SetItemMetadata(src, slot, metadata)

    return true
end

-- qs runs its own usable items on ESX and QBCore alike.
gg.inventory.registerUsable = function(item, cb)
    exports['qs-inventory']:CreateUsableItem(item, cb)

    return true
end

gg.inventory.getItemTable = function(item)
    local itemList = exports['qs-inventory']:GetItemList()
    if not item then return itemList end
    return itemList[item] or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-qs-inventory/html/images/%s.png', item)
end

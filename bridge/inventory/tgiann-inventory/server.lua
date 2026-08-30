gg.inventory = gg.inventory or {}

gg.inventory.canCarryitem = function(src, data)
    return exports["tgiann-inventory"]:CanCarryItem(src, data.item, data.count)
end

gg.inventory.hasItem = function(src, data)
    local inventory = gg.framework.GetInventory(src)
    if not inventory then
        return false, {err = "Failed to get inventory"}
    end
    local count = 0
    for k,v in pairs(inventory) do
        if v.name == data.item then
            count = count + v.amount
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

    local result = exports["tgiann-inventory"]:AddItem(src, data.item, data.count, data.slot, data.metadata, false)

    if result == false then return false end

    return true
end

gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local result = exports["tgiann-inventory"]:RemoveItem(src, data.item, data.count, data.slot, data.metadata)

    if result == false then return false end

    return true
end

gg.inventory.getItemTable = function(item)
    if not item then return exports["tgiann-inventory"]:Items() end
    return exports["tgiann-inventory"]:Items(item) or nil
end

gg.inventory.getImageUrl = function(item)
    return string.format('https://cfx-nui-inventory_images/images/%s.png', item)
end

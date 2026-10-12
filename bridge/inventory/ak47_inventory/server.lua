gg.inventory = gg.inventory or {}

local resource = "ak47_inventory"
local provider = resource

gg.inventory.getItemTable = function(item)
    return exports[provider]:Items(item) or nil
end

gg.inventory.getImageDirectory = function()
    return ("https://cfx-nui-%s/web/build/images/"):format(resource)
end

gg.inventory.getImageUrl = function(item, record)
    if type(item) ~= "string" or item == "" then return nil end

    if type(record) ~= "table" then
        local ok, value = pcall(gg.inventory.getItemTable, item)
        record = ok and type(value) == "table" and value or nil
    end

    local image = record and rawget(record, "image")
    local client = record and rawget(record, "client")

    if type(image) ~= "string" or image == "" then
        image = type(client) == "table" and rawget(client, "image") or nil
    end

    if type(image) ~= "string" or image == "" then image = item end
    if image:match("^https?://") or image:match("^nui://") then return image end
    if not image:match("%.%w+$") then image = image .. ".png" end

    return gg.inventory.getImageDirectory() .. image
end

gg.inventory.canCarryitem = function(src, data)
    return exports[provider]:CanAddItem(src, data.item, data.count or 1)
end

gg.inventory.hasItem = function(src, data)
    local item = exports[provider]:GetItem(src, data.item, nil, false)
    local count = type(item) == "table" and (tonumber(item.amount) or tonumber(item.count)) or 0

    return (count or 0) >= (data.count or 1)
end

gg.inventory.addItem = function(src, data)
    if not gg.inventory.canCarryitem(src, data) then return false end

    local result = exports[provider]:AddItem(src, data.item, data.count or 1, data.slot, data.metadata)

    return result ~= false
end

gg.inventory.removeItem = function(src, data)
    if not gg.inventory.hasItem(src, data) then return false end

    local result = exports[provider]:RemoveItem(src, data.item, data.count or 1, data.slot)

    return result ~= false
end

-- Rows read amount / info. Older ak47_qb_inventory builds without
-- GetInventoryItems keep the items in QBCore's PlayerData.
gg.inventory.getItems = function(src)
    local ok, items = pcall(function() return exports[provider]:GetInventoryItems(src) end)
    if ok and type(items) == "table" then return items end

    return gg.framework.GetInventory and gg.framework.GetInventory(src) or {}
end

gg.inventory.getSlot = function(src, slot)
    return exports[provider]:GetSlot(src, slot)
end

gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports[provider]:GetAmount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not exports[provider]:GetSlot(src, slot) then return false end

    exports[provider]:SetItemInfo(src, slot, metadata)

    return true
end

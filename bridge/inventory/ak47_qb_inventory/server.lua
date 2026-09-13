gg.inventory = gg.inventory or {}

local resource = "ak47_qb_inventory"
local provider = resource

local version = GetResourceMetadata(resource, "version", 0) or ""
local major, minor, patch = version:match("(%d+)%.(%d+)%.?(%d*)")
major, minor, patch = tonumber(major) or tonumber(version:match("%d+")) or 0, tonumber(minor) or 0, tonumber(patch) or 0

if major > 12 or (major == 12 and (minor > 5 or (minor == 5 and patch > 0))) then
    provider = "ak47_inventory"
end

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

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

gg.inventory.getItems = function()
    return exports[provider]:GetPlayerItems()
end

gg.inventory.getCount = function(item, metadata)
    if metadata then return nil end

    return exports[provider]:GetAmount(item)
end

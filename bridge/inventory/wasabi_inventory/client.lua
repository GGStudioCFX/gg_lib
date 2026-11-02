gg.inventory = gg.inventory or {}

local resource = "wasabi_inventory"
local directory

local function toNuiUrl(path)
    return (path:gsub("^nui://", "https://cfx-nui-"))
end

-- The owner can move the images with ImagePath in the client config. Anything
-- but a full address is relative to the inventory's own page, so it keeps the
-- folder the inventory ships with.
local function configuredPath()
    local config = LoadResourceFile(resource, "config/client/config.lua")

    if type(config) ~= "string" then return nil end

    for line in config:gmatch("[^\r\n]+") do
        local value = line:match("^%s*[%w_%.]*ImagePath%s*=%s*(.+)$")

        if value then
            for path in value:gmatch("['\"]([^'\"]+)['\"]") do
                if path:match("^https?://") or path:match("^nui://") then return path end
            end

            return nil
        end
    end

    return nil
end

gg.inventory.getImageDirectory = function()
    if not directory then
        local path = configuredPath() or ("nui://%s/ui/images"):format(resource)

        directory = toNuiUrl(path):gsub("/+$", "") .. "/"
    end

    return directory
end

gg.inventory.getItemTable = function(item)
    if not item then return exports.wasabi_inventory:ItemList() end

    return exports.wasabi_inventory:Items(item) or nil
end

gg.inventory.getImageUrl = function(item, record)
    if type(item) ~= "string" or item == "" then return nil end

    if type(record) ~= "table" then
        local ok, value = pcall(gg.inventory.getItemTable, item)

        record = ok and type(value) == "table" and value or nil
    end

    local client = record and rawget(record, "client")
    local image = type(client) == "table" and rawget(client, "image") or nil

    if type(image) ~= "string" or image == "" then image = item end
    if image:match("^https?://") or image:match("^nui://") then return toNuiUrl(image) end
    if not image:match("%.%w+$") then image = image .. ".png" end

    return gg.inventory.getImageDirectory() .. image
end

gg.inventory.getItems = function()
    return exports.wasabi_inventory:GetPlayerItems()
end

-- With metadata the shared layer counts from the rows, so a partial match reads
-- the same as on every other inventory.
gg.inventory.getCount = function(item, metadata)
    if metadata then return nil end

    return exports.wasabi_inventory:GetItemCount(item)
end

-- A use has already gone through by the time a script hears of it. An item with
-- a client export and a registered use lands here twice for one press.
local lastUse = {}

gg.inventory.useItem = function(data, cb)
    local key = type(data) == "table" and data.name and ("%s:%s"):format(data.name, data.slot)
    local now = GetGameTimer()
    local seen = key and lastUse[key]

    if seen and now - seen < 1000 then return end

    if key then lastUse[key] = now end

    cb(data)
end

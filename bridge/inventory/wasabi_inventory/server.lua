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

local function imageDirectory()
    if not directory then
        local path = configuredPath() or ("nui://%s/ui/images"):format(resource)

        directory = toNuiUrl(path):gsub("/+$", "") .. "/"
    end

    return directory
end

gg.inventory.canCarryitem = function(src, data)
    return exports.wasabi_inventory:CanCarryItem(src, data.item, data.count or 1, data.metadata)
end

gg.inventory.canCarryWeight = function(src, weight)
    return exports.wasabi_inventory:CanCarryWeight(src, weight)
end

gg.inventory.hasItem = function(src, data)
    return (exports.wasabi_inventory:GetItemCount(src, data.item) or 0) >= (data.count or 1)
end

gg.inventory.addItem = function(src, data)
    data.count = data.count or 1

    if not gg.inventory.canCarryitem(src, data) then return false end

    return (exports.wasabi_inventory:AddItem(src, data.item, data.count, data.metadata, data.slot))
end

-- A slot already names the stack, and metadata beside it would have to match the
-- whole table where the shared layer only asked for some keys.
gg.inventory.removeItem = function(src, data)
    data.count = data.count or 1

    local has, why = gg.inventory.hasItem(src, data)

    if not has then return false, why end

    local metadata = data.slot == nil and data.metadata or nil

    return (exports.wasabi_inventory:RemoveItem(src, data.item, data.count, metadata, data.slot))
end

gg.inventory.getItems = function(src)
    return exports.wasabi_inventory:GetInventoryItems(src)
end

gg.inventory.getSlot = function(src, slot)
    return exports.wasabi_inventory:GetSlot(src, slot)
end

-- With metadata the shared layer counts from the rows, so a partial match reads
-- the same as on every other inventory.
gg.inventory.getCount = function(src, item, metadata)
    if metadata then return nil end

    return exports.wasabi_inventory:GetItemCount(src, item)
end

gg.inventory.setMetadata = function(src, slot, metadata)
    if not exports.wasabi_inventory:GetSlot(src, slot) then return false end

    exports.wasabi_inventory:SetMetadata(src, slot, metadata)

    return true
end

-- The callback names the slot; the slot's row carries the count and metadata.
gg.inventory.registerUsable = function(item, cb)
    exports.wasabi_inventory:registerUsableItem(item, function(inventoryId, used, context)
        local slot = type(context) == "table" and context.slot or nil

        cb(inventoryId, slot and exports.wasabi_inventory:GetSlot(inventoryId, slot) or used)
    end)

    return true
end

gg.inventory.onSwap = function(cb, options)
    return exports.wasabi_inventory:registerHook('swapItems', cb, options)
end

gg.inventory.removeHook = function(id)
    exports.wasabi_inventory:removeHooks(id)

    return true
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

    return imageDirectory() .. image
end

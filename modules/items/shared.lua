
gg.items = gg.items or {}

local catalogue = nil
local resolved = false

local function imageBase(record, key)
    local named = record.image

    if type(named) ~= "string" or named == "" then
        local client = record.client

        named = type(client) == "table" and client.image or nil
    end

    if type(named) == "string" and named ~= "" then
        return (named:gsub("%.%w+$", ""))
    end

    return record.name or key
end

local function storedPattern()
    local stored

    if settings and settings.generic and settings.generic.get then
        stored = settings.generic.get("items.image_url")
    end

    if (stored == nil or stored == "") and GenericSettings and GenericSettings.get then
        stored = GenericSettings.get("items.image_url")
    end

    if type(stored) ~= "string" or stored == "" then return nil end

    return stored
end

function gg.items.normalize(key, record)
    if type(record) ~= "table" then return nil end
    if rawget(record, "__cfx_functionReference") then return nil end

    local meta = getmetatable(record)
    if type(meta) == "table" and rawget(meta, "__call") then return nil end

    local name = record.name or key

    if type(name) ~= "string" or name == "" then return nil end

    local base  = imageBase(record, key)
    local image

    local pattern = storedPattern()

    if pattern then
        local ok, built = pcall(string.format, pattern, base)

        image = ok and built or nil
    elseif gg.inventory and gg.inventory.getImageUrl then
        local ok, url = pcall(gg.inventory.getImageUrl, base, record)

        image = ok and url or nil
    end

    return {
        name        = name,
        label       = type(record.label) == "string" and record.label or name,
        weight      = tonumber(record.weight) or 0,
        description = record.description,
        stack       = record.stack ~= false,
        image       = image,
    }
end

local function rawTable()
    if not (gg.inventory and gg.inventory.getItemTable) then return nil end

    local ok, list = pcall(gg.inventory.getItemTable)

    if ok and type(list) == "table" then return list end

    if GetResourceState("ox_inventory") == "started" then
        local fellback, items = pcall(function() return exports.ox_inventory:Items() end)

        if fellback and type(items) == "table" then return items end
    end

    return nil
end

local function build()
    local list = rawTable()
    if not list then return false end

    local out, total = {}, 0

    for key, record in pairs(list) do
        local ok, item = pcall(gg.items.normalize, key, record)

        if ok and item then
            out[item.name] = item
            total = total + 1
        elseif not ok and gg.print and gg.print.warn then
            gg.print.warn(("skipped item '%s' while building the catalogue: %s"):format(tostring(key), tostring(item)))
        end
    end

    if total == 0 then return false end

    catalogue = out
    resolved  = true

    return true
end

function gg.items.all()
    if not resolved then build() end

    return catalogue or {}
end

function gg.items.get(name)
    if type(name) ~= "string" then return nil end

    return gg.items.all()[name]
end

function gg.items.label(name)
    local item = gg.items.get(name)

    return item and item.label or name
end

function gg.items.image(name)
    local item = gg.items.get(name)

    return item and item.image or nil
end

function gg.items.exists(name)
    return gg.items.get(name) ~= nil
end

function gg.items.list()
    local out = {}

    for _, item in pairs(gg.items.all()) do out[#out + 1] = item end

    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)

    return out
end

function gg.items.ready()
    return resolved
end

function gg.items.await(timeout)
    local deadline = GetGameTimer() + (tonumber(timeout) or 30000)

    while not resolved do
        if GetGameTimer() > deadline then return false end

        Wait(100)
    end

    return true
end

function gg.items.refresh()
    local previous, wasResolved = catalogue, resolved

    resolved, catalogue = false, nil

    if build() then return true end

    catalogue, resolved = previous, wasResolved

    return false
end

local WARM_TRIES = 60

if gg.context == "server" then
    CreateThread(function()
        local wired = gg.bridge and gg.bridge.inventory

        if not wired or wired == "default" then return end

        for _ = 1, WARM_TRIES do
            if GetResourceState(wired) == "started" and build() then return end

            Wait(1000)
        end

        if gg.print and gg.print.warn then
            gg.print.warn(("could not read the item list from %s"):format(wired))
        end
    end)
end

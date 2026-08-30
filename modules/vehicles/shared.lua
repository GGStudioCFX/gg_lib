
gg.vehicles = gg.vehicles or {}

local RESOURCE = GetCurrentResourceName()
local CHANNEL  = ("%s:vehicles:catalogue"):format(RESOURCE)

local catalogue = nil
local byHash    = nil
local resolved  = false

function gg.vehicles.normalize(row)
    if type(row) ~= "table" then return nil end

    local model = row.model or row.spawn_code or row.spawncode or row.vehicle

    if type(model) ~= "string" or model == "" then return nil end

    model = model:lower()

    local price = tonumber(row.price)

    return {
        model    = model,
        label    = row.label or row.name or model,
        brand    = row.brand,
        price    = price and price >= 0 and price or nil,
        category = row.category,
    }
end

local DEALERSHIP = "jg-dealerships"

local SPAWN_COLUMNS = { "spawn_code", "model", "vehicle", "spawncode" }
local LABEL_COLUMNS = { "name", "label", "model_name" }

local function firstPresent(columns, candidates)
    for _, candidate in ipairs(candidates) do
        if columns[candidate] then return candidate end
    end

    return nil
end

local function dealershipRows()
    local listed, tables = pcall(MySQL.query.await, "SHOW TABLES LIKE 'dealership%'")

    if not listed or type(tables) ~= "table" then return nil end

    for _, entry in ipairs(tables) do
        local name

        for _, value in pairs(entry) do
            if type(value) == "string" then name = value end
        end

        if name then
            local described, columns = pcall(MySQL.query.await, ("SHOW COLUMNS FROM `%s`"):format(name))

            if described and type(columns) == "table" then
                local present = {}

                for _, column in ipairs(columns) do
                    if type(column.Field) == "string" then present[column.Field] = true end
                end

                local spawn = firstPresent(present, SPAWN_COLUMNS)

                if spawn and present.price then
                    local label  = firstPresent(present, LABEL_COLUMNS)
                    local fields = { ("`%s` AS model"):format(spawn), "`price`" }

                    if label then fields[#fields + 1] = ("`%s` AS name"):format(label) end
                    if present.brand then fields[#fields + 1] = "`brand`" end
                    if present.category then fields[#fields + 1] = "`category`" end

                    local read, rows = pcall(MySQL.query.await,
                        ("SELECT %s FROM `%s`"):format(table.concat(fields, ", "), name))

                    if read and type(rows) == "table" and rows[1] then return rows end
                end
            end
        end
    end

    return nil
end

local function rawRows()
    if gg.context == "server" and GetResourceState(DEALERSHIP) == "started" then
        local rows = dealershipRows()

        if rows then return rows end
    end

    if not (gg.framework and gg.framework.GetVehicleTable) then return nil end

    local ok, rows = pcall(gg.framework.GetVehicleTable)

    return ok and type(rows) == "table" and rows or nil
end

local function absorb(rows)
    if type(rows) ~= "table" then return false end

    local out, hashes, total = {}, {}, 0

    for _, row in ipairs(rows) do
        local vehicle = gg.vehicles.normalize(row)

        if vehicle and not out[vehicle.model] then
            out[vehicle.model] = vehicle
            hashes[joaat(vehicle.model)] = vehicle
            total = total + 1
        end
    end

    if total == 0 then return false end

    catalogue, byHash = out, hashes
    resolved = true

    return true
end

local function build()
    return absorb(rawRows())
end

function gg.vehicles.all()
    if not resolved and gg.context == "server" then build() end

    return catalogue or {}
end

function gg.vehicles.get(model)
    if type(model) ~= "string" then return nil end

    return gg.vehicles.all()[model:lower()]
end

function gg.vehicles.fromHash(hash)
    if not resolved and gg.context == "server" then build() end

    local vehicle = byHash and byHash[hash]

    return vehicle and vehicle.model or nil
end

function gg.vehicles.label(model)
    local vehicle = gg.vehicles.get(model)

    return vehicle and vehicle.label or model
end

function gg.vehicles.price(model)
    local vehicle = gg.vehicles.get(model)

    return vehicle and vehicle.price or nil
end

function gg.vehicles.exists(model)
    return gg.vehicles.get(model) ~= nil
end

function gg.vehicles.list()
    local out = {}

    for _, vehicle in pairs(gg.vehicles.all()) do out[#out + 1] = vehicle end

    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)

    return out
end

function gg.vehicles.categories()
    local seen, out = {}, {}

    for _, vehicle in pairs(gg.vehicles.all()) do
        if vehicle.category and not seen[vehicle.category] then
            seen[vehicle.category] = true
            out[#out + 1] = vehicle.category
        end
    end

    table.sort(out)

    return out
end

function gg.vehicles.ready()
    return resolved
end

function gg.vehicles.await(timeout)
    local deadline = GetGameTimer() + (tonumber(timeout) or 30000)

    while not resolved do
        if GetGameTimer() > deadline then return false end

        Wait(100)
    end

    return true
end

local WARM_TRIES = 60

if gg.context == "server" then
    function gg.vehicles.refresh()
        local previous, wasResolved, previousHashes = catalogue, resolved, byHash

        resolved, catalogue, byHash = false, nil, nil

        if build() then return true end

        catalogue, resolved, byHash = previous, wasResolved, previousHashes

        return false
    end

    GGCallback.register(CHANNEL, function()
        return gg.vehicles.all()
    end)

    CreateThread(function()
        local wired = gg.bridge and gg.bridge.framework

        if not wired or wired == "default" then return end

        for _ = 1, WARM_TRIES do
            if GetResourceState(wired) == "started" and build() then return end

            Wait(1000)
        end

        if gg.print and gg.print.warn then
            gg.print.warn(("could not read the vehicle list from %s"):format(wired))
        end
    end)
else
    function gg.vehicles.refresh()
        local ok, rows = pcall(GGCallback.await, CHANNEL)

        if not ok or type(rows) ~= "table" then return false end

        local list = {}

        for _, vehicle in pairs(rows) do list[#list + 1] = vehicle end

        return absorb(list)
    end

    CreateThread(function()
        for _ = 1, WARM_TRIES do
            if gg.vehicles.refresh() then return end

            Wait(1000)
        end
    end)
end

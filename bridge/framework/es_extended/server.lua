gg.framework = gg.framework or {}

local ESX = exports.es_extended:getSharedObject()
local ox_inventory = GetResourceState('ox_inventory') == 'started' and true or false

gg.framework.GetIdentifier = function(source)
    if not source then return nil end
    local player = ESX.GetPlayerFromId(source)
    if not player then return nil end
    return tostring(player.getIdentifier())
end

gg.framework.GetName = function(source)
    local player = ESX.GetPlayerFromId(source)
    if not player then return "" end
    return player.getName()
end

gg.framework.GetNameByIdentifier = function(identifier)
    if identifier then
        local result = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
        if result and result[1] then
            local fn, ln = result[1].firstname, result[1].lastname
            local name = fn..' '..ln
            return name
        end
    end
    identifier = identifier or "No Id"
    return "No Name Found - " .. identifier
end

gg.framework.getItemTable = function(item)
    return "Item Data" -- ESX inventories handle this
end

gg.framework.GetPlayerJobInfo = function(source)
    local player = ESX.GetPlayerFromId(source)
    local job = player.getJob()
    local jobInfo = {
        name = job.name,
        label = job.label,
        grade = job.grade,
        gradeName = job.grade_label,
    }
    return jobInfo
end

gg.framework.GetPlayers = function()
    local players = ESX.GetExtendedPlayers()
    local formattedPlayers = {}
    for _, v in pairs(players) do
        local player = {
            job = v.getJob().name,
            gang = false,
            source = v.source,
            onDuty = false,
        }
        table.insert(formattedPlayers, player)
    end
    return formattedPlayers
end

gg.framework.GetSex = function(source)
    local player = ESX.GetPlayerFromId(source)
    return player.variables.sex
end

gg.framework.GetInventory = function(source)
    local player = ESX.GetPlayerFromId(source)
    local items = {}
    local data = ox_inventory and exports.ox_inventory:GetInventoryItems(source) or player.getInventory()

    for slot, item in pairs(data) do
        table.insert(items, {
            name = item.name,
            label = item.label,
            slot = slot,
            count = ox_inventory and item.count or item.amount,
            weight = item.weight,
            metadata = ox_inventory and item.metadata or item.info
        })
    end

    return items
end
gg.framework.RegisterUsableItem = function(item, cb)
    ESX.RegisterUsableItem(item, cb)
end

local ACCOUNTS = {
    cash  = "money",
    bank  = "bank",
    black = "black_money",
}

local function accountOf(name)
    return ACCOUNTS[name] or name
end

local function balance(xPlayer, account)
    local held = xPlayer.getAccount(accountOf(account))

    return held and tonumber(held.money) or 0
end

gg.framework.GetMoney = function(source, account)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return 0 end

    return balance(xPlayer, account)
end

gg.framework.AddMoney = function(source, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    xPlayer.addAccountMoney(accountOf(account), amount, reason)

    return true
end

gg.framework.RemoveMoney = function(source, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    if balance(xPlayer, account) < amount then return false end

    xPlayer.removeAccountMoney(accountOf(account), amount, reason)

    return true
end

gg.framework.SetJob = function(source, jobId, grade)
    local player = ESX.GetPlayerFromId(source)
    if not player then return false end
    player.setJob(jobId, tonumber(grade) or 0)
    return true
end

local vehicle_storage = {}
local last_ret = 0

gg.framework.GetVehicle = function(vehicle)
    if not vehicle or type(vehicle) ~= "string" then
        return nil
    end

    if (last_ret + 600) < os.time() then
        vehicle_storage = {}

        local function safeQuery(sql, retries, delay)
            retries = retries or 5
            delay = delay or 1000

            for i = 1, retries do
                local ok, result = pcall(function()
                    return MySQL.query.await(sql)
                end)

                if ok and result and #result > 0 then
                    return result
                end

                Wait(delay)
            end

            return {}
        end

        local results = safeQuery("SELECT name, model FROM vehicles", 10, 3000)

        if results and type(results) == "table" then
            for _, row in ipairs(results) do
                if row.model and row.name then
                    vehicle_storage[row.model] = row.name
                end
            end
        end

        last_ret = os.time()
    end

    return vehicle_storage[vehicle] or vehicle
end

local vehicle_list = {}
local last_request = 0
GGCallback.register(GetCurrentResourceName()..":server:retrieveVehicleList", function()
     if (last_request + 600) < os.time() then
        vehicle_list = {}
        local results = MySQL.query.await("SELECT model FROM vehicles")
        if not results or next(results) == nil then
            return {}
        end
        vehicle_list = results
        last_request = os.time()
    end

    return vehicle_list or {}
end)

gg.framework.getItemLabel = function(item)
    if not item then return nil end

    if GetResourceState("qs-inventory") == "started" then
        local itemList = exports["qs-inventory"]:GetItemList()
        return (itemList[item] and itemList[item].label) or item
    elseif GetResourceState("core_inventory") == "started" then
        return item
    elseif GetResourceState("ox_inventory") == "started" then
        local itemData = exports.ox_inventory:Items(item)
        return (itemData and itemData.label) or item
    end

    return item
end

gg.framework.GetVehicleTable = function()
    local ok, results = pcall(MySQL.query.await, "SELECT name, model, price, category FROM vehicles")

    if not ok or not results then
        ok, results = pcall(MySQL.query.await, "SELECT name, model FROM vehicles")
    end

    if not ok or not results then return {} end

    local out = {}
    for _, row in ipairs(results) do
        if row.model then
            out[#out + 1] = {
                model    = row.model,
                label    = row.name or row.model,
                price    = tonumber(row.price),
                category = row.category,
            }
        end
    end
    return out
end

gg.framework.GetUniquePlate = function()
    local letters, numbers = {}, {}

    for c = 65, 90 do letters[#letters+1] = string.char(c) end
    for c = 48, 57 do numbers[#numbers+1] = string.char(c) end

    local function rand(tbl)
        return tbl[math.random(#tbl)]
    end

    while true do
        local plate = ""

        plate = plate .. rand(numbers)
        plate = plate .. rand(letters)
        plate = plate .. rand(letters)
        plate = plate .. rand(numbers)
        plate = plate .. rand(numbers)
        plate = plate .. rand(numbers)
        plate = plate .. rand(letters)
        plate = plate .. rand(letters)
        
        local exists = MySQL.scalar.await(
            "SELECT 1 FROM owned_vehicles WHERE plate = ? LIMIT 1",
            { plate }
        )

        if not exists then
            return plate
        end
    end
end

gg.framework.InsertVehiclePlayerGarage = function(payload)
    local src = payload.source
    local identifier = gg.framework.GetIdentifier(src)
    local license = GetPlayerIdentifierByType(src, "license")

    if not license or license == "" then
        for _, v in ipairs(GetPlayerIdentifiers(src)) do
            if v:sub(1, 8) == "license:" then
                license = v
                break
            end
        end
    end

    local valid_plate = payload.plate
    local result = MySQL.scalar.await(
        "SELECT 1 FROM owned_vehicles WHERE plate = ? LIMIT 1",
        { valid_plate }
    )

    if result then
        valid_plate = gg.framework.GetUniquePlate()
    end

    MySQL.insert(
        "INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, stored, parking, pound, mileage, glovebox, trunk) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        {
            identifier,
            valid_plate,
            json.encode(payload.mods or {}),
            payload.type or "car",
            payload.job or nil,
            1,
            payload.garage or nil,
            nil, 
            0.0,
            nil,
            nil
        }
    )

    return true
end

local function playerLoaded(source)
    if not source then return end

    TriggerEvent(("%s:server:OnPlayerLoaded"):format(GetCurrentResourceName()), source)
end

AddEventHandler("esx:playerLoaded", function(source, xPlayer)
    playerLoaded(source or (xPlayer and xPlayer.source))
end)

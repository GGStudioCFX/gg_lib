gg.framework = gg.framework or {}

local QBCore = exports['qb-core']:GetCoreObject()
local ox_inventory = GetResourceState('ox_inventory') == 'started' and true or false

gg.framework.GetIdentifier = function(source)
    if not source then return nil end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return nil end
    return tostring(player.PlayerData.citizenid)
end

gg.framework.GetName = function(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return "" end
    return player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
end

gg.framework.GetNameByIdentifier = function(identifier)
    if identifier then
        local result = MySQL.query.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
        if result and result[1] then
            local charInfo = json.decode(result[1].charinfo)
            return charInfo.firstname .. ' ' .. charInfo.lastname
        end
    end
    identifier = identifier or "No Id"
    return "No Name Found - " .. identifier
end

gg.framework.GetPlayers = function()
    local players = QBCore.Functions.GetQBPlayers()
    local formattedPlayers = {}
    for _, v in pairs(players) do
        local player = {
            job = v.PlayerData.job.name,
            gang = v.PlayerData.gang.name,
            source = v.PlayerData.source,
            onDuty = v.PlayerData.job.onduty,
        }
        table.insert(formattedPlayers, player)
    end
    return formattedPlayers
end

gg.framework.GetPlayerJobInfo = function(source)
    local player = QBCore.Functions.GetPlayer(source)
    local job = player.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade,
        gradeName = job.grade.name,
    }
end

gg.framework.GetSex = function(source)
    local player = QBCore.Functions.GetPlayer(source)
    return player.PlayerData.charinfo.gender
end

gg.framework.GetInventory = function(source)
    local player = QBCore.Functions.GetPlayer(source)
    local items = {}
    local data = ox_inventory and exports.ox_inventory:GetInventoryItems(source) or player.PlayerData.items
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

gg.framework.getItemTable = function(item)
    if not item then return QBCore.Shared.Items end
    return QBCore.Shared.Items[item] or nil
end

gg.framework.RegisterUsableItem = function(item, cb)
    QBCore.Functions.CreateUseableItem(item, cb)
end

local ACCOUNTS = {
    cash   = "cash",
    bank   = "bank",
    black  = "black_money",
    crypto = "crypto",
}

local function accountOf(name)
    return ACCOUNTS[name] or name
end

gg.framework.GetMoney = function(source, account)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return 0 end

    return player.PlayerData.money[accountOf(account)] or 0
end

gg.framework.AddMoney = function(source, account, amount, reason)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    return player.Functions.AddMoney(accountOf(account), amount, reason) == true
end

gg.framework.RemoveMoney = function(source, account, amount, reason)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    if (player.PlayerData.money[accountOf(account)] or 0) < amount then return false end

    return player.Functions.RemoveMoney(accountOf(account), amount, reason) == true
end

gg.framework.SetJob = function(source, jobId, grade)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end
    player.Functions.SetJob(jobId, tonumber(grade) or 0)
    return true
end

gg.framework.GetVehicle = function(vehicle)
    if not vehicle then return vehicle or "" end
    local vehicle_data = QBCore.Shared.Vehicles[vehicle]
    if type(vehicle_data) == "table" and vehicle_data.name then
        return vehicle_data.name
    end
    return vehicle
end

gg.framework.getItemLabel = function(item)
    local itemData = QBCore.Shared.Items[item]
    return (itemData and itemData.label) or item
end

gg.framework.GetVehicleTable = function()
    local out = {}
    local vehicles = QBCore.Shared.Vehicles
    if type(vehicles) == "table" then
        for model, data in pairs(vehicles) do
            out[#out + 1] = {
                model    = type(data.model) == "string" and data.model or tostring(model),
                label    = data.name or tostring(model),
                brand    = data.brand,
                price    = tonumber(data.price),
                category = data.category,
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
            "SELECT 1 FROM player_vehicles WHERE plate = ? LIMIT 1",
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
        "SELECT 1 FROM player_vehicles WHERE plate = ? LIMIT 1",
        { valid_plate }
    )

    if result then
        valid_plate = gg.framework.GetUniquePlate()
    end

    MySQL.insert(
        "INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, garage) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        {
            license,
            identifier,
            payload.vehicle,
            GetHashKey(payload.vehicle),
            json.encode(payload.mods),
            valid_plate,
            0,
            payload.garage or nil,
        }
    )

    return true
end

local function playerLoaded(source)
    if not source then return end

    TriggerEvent(("%s:server:OnPlayerLoaded"):format(GetCurrentResourceName()), source)
end

AddEventHandler("QBCore:Server:OnPlayerLoaded", function(player)
    playerLoaded(player and player.PlayerData and player.PlayerData.source)
end)

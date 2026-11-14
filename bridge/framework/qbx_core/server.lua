gg.framework = gg.framework or {}

local qbx_core = exports['qbx_core']
local ox_inventory = exports['ox_inventory']

gg.framework.GetIdentifier = function(source)
    if not source then return nil end
    local player = qbx_core:GetPlayer(source)
    if not player then return nil end
    return tostring(player.PlayerData.citizenid)
end

gg.framework.GetName = function(source)
    local player = qbx_core:GetPlayer(source)
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
    local players = qbx_core:GetQBPlayers()
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
    local player = qbx_core:GetPlayer(source)
    local job = player.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade,
        gradeName = job.grade.name,
    }
end

gg.framework.GetSex = function(source)
    local player = qbx_core:GetPlayer(source)
    return player.PlayerData.charinfo.gender
end

gg.framework.GetInventory = function(source)
    local player = qbx_core:GetPlayer(source)
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
    return "Item Data" -- Qbox Inventory Handles This
end

gg.framework.RegisterUsableItem = function(item, cb)
    qbx_core:CreateUseableItem(item, cb)
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
    local player = qbx_core:GetPlayer(source)
    if not player then return 0 end

    return player.PlayerData.money[accountOf(account)] or 0
end

gg.framework.AddMoney = function(source, account, amount, reason)
    local player = qbx_core:GetPlayer(source)
    if not player then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    return player.Functions.AddMoney(accountOf(account), amount, reason) == true
end

gg.framework.RemoveMoney = function(source, account, amount, reason)
    local player = qbx_core:GetPlayer(source)
    if not player then return false end

    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end

    if (player.PlayerData.money[accountOf(account)] or 0) < amount then return false end

    return player.Functions.RemoveMoney(accountOf(account), amount, reason) == true
end

gg.framework.SetJob = function(source, jobId, grade)
    local Player = qbx_core:GetPlayer(source)
    if not Player then return false end
    Player.Functions.SetJob(jobId, tonumber(grade) or 0)
    return true
end

gg.framework.GetVehicle = function(vehicle)
    if not vehicle then return vehicle or "" end
    local vehicle_data = qbx_core:GetVehiclesByName(vehicle)
    if type(vehicle_data) == "table" and vehicle_data.name then
        return vehicle_data.name
    end
    return vehicle
end

gg.framework.getItemLabel = function(item)
    local itemData = exports.ox_inventory:Items(item)
    return (itemData and itemData.label) or item
end

gg.framework.GetVehicleTable = function()
    local out = {}
    local vehicles = qbx_core:GetVehiclesByName()
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
    local license = GetPlayerIdentifierByType(src, "license2")

    if not license or license == "" then
        for _, v in ipairs(GetPlayerIdentifiers(src)) do
            if v:sub(1, 8) == "license2:" then
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
            payload.state or 0,
            payload.garage or nil,
        }
    )

    return true
end

local loadedPlayers = {}

local function playerLoaded(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then return end

    local current = qbx_core:GetPlayer(playerSource)
    local identifier = current and current.PlayerData and current.PlayerData.citizenid

    if not identifier or loadedPlayers[playerSource] == identifier then return end

    loadedPlayers[playerSource] = identifier
    TriggerEvent(("%s:server:OnPlayerLoaded"):format(GetCurrentResourceName()), playerSource)
end

RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function(player)
    local playerSource = tonumber(source)

    -- A network caller can only announce its own server-side player.
    if not playerSource or playerSource <= 0 then
        playerSource = type(player) == "table" and type(player.PlayerData) == "table"
            and tonumber(player.PlayerData.source) or nil
    end

    playerLoaded(playerSource)
end)

AddEventHandler("qbx_core:server:onPlayerLoaded", function(playerSource)
    playerLoaded(playerSource)
end)

local function playerUnloaded(playerSource)
    loadedPlayers[tonumber(playerSource) or 0] = nil
end

AddEventHandler("QBCore:Server:OnPlayerUnload", playerUnloaded)
AddEventHandler("qbx_core:server:playerLoggedOut", playerUnloaded)

AddEventHandler("playerDropped", function()
    playerUnloaded(source)
end)

--------------------------------------------------
-- MARK: Jobs
--------------------------------------------------

-- gg.framework.CreateJob(name, def) makes a job the server does not have yet, the framework's own way, and never
-- changes one it has. def: label, type, defaultDuty, offDutyPay and grades = { [0] = { name, payment, isboss,
-- bankAuth }, ... } (keys are the grade numbers). Returns true once the framework shows the job, or false, why
-- ("exists" when the server already has it). gg.framework.GetJob(name) is the framework's own job table, or nil.

local function jobNameOk(name)
    return type(name) == "string" and #name <= 50 and name:match("^[%w_%-]+$") ~= nil
end

-- The grades sorted: { grade, name, payment, isboss, bankAuth }, or nil and why.
local function jobGrades(def)
    if type(def) ~= "table" or type(def.grades) ~= "table" then return nil, "a job needs grades" end

    local list, seen = {}, {}

    for key, grade in pairs(def.grades) do
        local level = type(grade) == "table" and tonumber(grade.grade or key) or nil

        if not level or level < 0 or level % 1 ~= 0 then
            return nil, ("grade %s is not a whole number of 0 or more"):format(tostring(key))
        end

        level = math.floor(level)

        if seen[level] then return nil, ("grade %d is given twice"):format(level) end

        seen[level] = true

        list[#list + 1] = {
            grade    = level,
            name     = type(grade.name) == "string" and grade.name ~= "" and grade.name or ("Grade %d"):format(level),
            payment  = math.max(0, math.floor(tonumber(grade.payment or grade.salary) or 0)),
            isboss   = grade.isboss == true,
            bankAuth = grade.bankAuth == true,
        }
    end

    if #list == 0 then return nil, "a job needs at least one grade" end

    table.sort(list, function(a, b) return a.grade < b.grade end)

    return list
end

local function jobLabel(def, name)
    return type(def.label) == "string" and def.label ~= "" and def.label or name
end

gg.framework.GetJob = function(name)
    if type(name) ~= "string" or name == "" then return nil end

    local ok, job = pcall(function() return qbx_core:GetJob(name) end)

    return ok and type(job) == "table" and job or nil
end

-- qbx_core keeps a made job in memory for this run (shared/jobs.lua is not written), so the caller makes it again
-- at each start, before players join.
gg.framework.CreateJob = function(name, def)
    if not jobNameOk(name) then return false, "a job name is letters, digits, _ and - (up to 50)" end
    if gg.framework.GetJob(name) then return false, "exists" end

    local list, why = jobGrades(def)

    if not list then return false, why end

    local grades = {}

    for _, g in ipairs(list) do
        grades[g.grade] = { name = g.name, payment = g.payment, isboss = g.isboss or nil, bankAuth = g.bankAuth or nil }
    end

    local job = {
        label       = jobLabel(def, name),
        type        = type(def.type) == "string" and def.type or nil,
        defaultDuty = def.defaultDuty ~= false,
        offDutyPay  = def.offDutyPay == true,
        grades      = grades,
    }

    local ok, made, message = pcall(function() return qbx_core:CreateJob(name, job) end)

    if not ok then return false, tostring(made) end
    if made == false then return false, tostring(message or "qbx_core refused it") end
    if not gg.framework.GetJob(name) then return false, "qbx_core does not show it" end

    return true
end

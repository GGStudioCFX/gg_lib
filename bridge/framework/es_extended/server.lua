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

    local ok, job = pcall(function()
        local jobs = ESX.GetJobs and ESX.GetJobs() or ESX.Jobs

        return jobs and jobs[name]
    end)

    return ok and type(job) == "table" and job or nil
end

local function gradeId(label)
    return (label:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- es_extended keeps jobs in its database (jobs, job_grades), so a made job stays. ESX.CreateJob where this ESX has
-- it; else the two tables written here and ESX.RefreshJobs, so it shows in this run. A grade's name is its id in
-- ESX: the boss grade is 'boss' (what ESX's own society scripts look for), the rest from their labels.
gg.framework.CreateJob = function(name, def)
    if not jobNameOk(name) then return false, "a job name is letters, digits, _ and - (up to 50)" end
    if gg.framework.GetJob(name) then return false, "exists" end

    local list, why = jobGrades(def)

    if not list then return false, why end

    local label = jobLabel(def, name)
    local grades, used = {}, {}

    for _, g in ipairs(list) do
        local id = g.isboss and not used.boss and "boss" or gradeId(g.name)

        if id == "" or used[id] then id = ("grade_%d"):format(g.grade) end

        used[id] = true
        grades[#grades + 1] = { grade = g.grade, name = id, label = g.name, salary = g.payment }
    end

    if ESX.CreateJob then
        local ok, made = pcall(ESX.CreateJob, name, label, grades)

        if not ok then return false, tostring(made) end
        if not made then return false, "es_extended refused it (see its console line)" end
        if not gg.framework.GetJob(name) then return false, "es_extended does not show it" end

        return true
    end

    if type(MySQL) ~= "table" then return false, "no database to write the job to" end
    if not ESX.RefreshJobs then return false, "this es_extended cannot load a new job without a restart" end

    local queries = { { query = "INSERT INTO jobs (name, label) VALUES (?, ?)", values = { name, label } } }

    for _, g in ipairs(grades) do
        queries[#queries + 1] = {
            query  = "INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, ?, ?, ?, ?, ?, ?)",
            values = { name, g.grade, g.name, g.label, g.salary, "{}", "{}" },
        }
    end

    local ok, made = pcall(MySQL.transaction.await, queries)

    if not ok then return false, tostring(made) end
    if not made then return false, "the database refused it" end

    pcall(ESX.RefreshJobs)

    if not gg.framework.GetJob(name) then return false, "saved, but es_extended does not show it yet" end

    return true
end

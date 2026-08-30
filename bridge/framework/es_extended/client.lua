gg.framework = gg.framework or {}

local ESX = exports.es_extended:getSharedObject()
local PlayerData = ESX.GetPlayerData()

gg.framework.getItemTable = function(item)
    if not item then return exports.ox_inventory:Items() end
    local itemData = exports.ox_inventory:Items(item)
    return itemData or item
end

gg.framework.GetPlayerGroupInfo = function()
    local jobInfo = {
        name = PlayerData.job.name,
        grade = PlayerData.job.grade,
        label = PlayerData.job.label
    }
    return jobInfo
end

local cachedVehicles = {}
local lastVehicleRequest = 0
local cacheDuration = 600000    -- 10 Minutes until able to refresh

gg.framework.ValidateVehicleHash = function(modelHash)
    if not modelHash then return 0 end

    if (GetGameTimer() - lastVehicleRequest) > cacheDuration then
        cachedVehicles = GGCallback.await(("%s:server:retrieveVehicleList"):format(GetCurrentResourceName())) or {}
        lastVehicleRequest = GetGameTimer()
    end

    for _, vehicle in pairs(cachedVehicles) do
        if joaat(vehicle.model) == modelHash then
            return vehicle.model
        end
    end

    return false
end

AddEventHandler('esx:onPlayerSpawn', function(noAnim)
    TriggerEvent(GetCurrentResourceName()..':client:OnPlayerLoaded')
    TriggerEvent(GetCurrentResourceName()..':client:onResourceStart')
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('esx:playerLoaded', function()
    PlayerData = ESX.GetPlayerData()
    TriggerServerEvent(GetCurrentResourceName()..':server:OnPlayerLoaded')
end)

gg.framework = gg.framework or {}

local qbx_core = exports['qbx_core']

gg.framework.getItemTable = function(item)
    if not item then return exports.ox_inventory:Items() end
    local itemData = exports.ox_inventory:Items(item)
    return itemData or item
end

gg.framework.GetPlayerGroupInfo = function(job)
    local Player = qbx_core:GetPlayerData()
    local info 
    if job then 
        info = {
            name = Player.job.name,
            grade = Player.job.grade.level,
            label = Player.job.label
        }
    else 
        info = {
            name = Player.gang.name,
            grade = Player.gang.grade.level,
            label = Player.gang.label
        }
    end
    return info
end

gg.framework.ValidateVehicleHash = function(modelHash)
    if not modelHash then return modelHash or 0 end
    local vehicle_data = qbx_core:GetVehiclesByName()

    for k,v in pairs(vehicle_data) do
        if joaat(v.model) == modelHash then
            return v.model
        end
    end

    return false
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerEvent(GetCurrentResourceName()..':client:OnPlayerLoaded')
    TriggerEvent(GetCurrentResourceName()..':client:onResourceStart')
    TriggerServerEvent(GetCurrentResourceName()..':server:OnPlayerLoaded')
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
end)

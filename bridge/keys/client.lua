-- Some key scripts only honor a key request made beside the car, and a depot
-- hands its keys over at a desk. Those go through this resource's server, with
-- the plain request kept for a car the server will not vouch for.
local GRANT   = GetCurrentResourceName() .. ":gg_keys"
local WAIT_MS = { add = 5000, remove = 2000 }

local function viaServer(action, veh, fallback)
    if GetResourceState("qbx_vehiclekeys") ~= "started" or not NetworkGetEntityIsNetworked(veh) then
        return fallback()
    end

    local answered = promise.new()
    local settled = false

    local function settle(granted)
        if settled then return end

        settled = true

        answered:resolve(granted == true or fallback())
    end

    gg.callback.request(GRANT, settle, action, VehToNet(veh))

    SetTimeout(WAIT_MS[action], settle)

    -- A car is usually deleted straight after its key is taken back, and once
    -- it is gone the server has nothing left to take the key from.
    if action == "remove" and coroutine.isyieldable() then
        return Citizen.Await(answered)
    end

    return true
end

local providers = {
    ['0r-vehiclekeys'] = {
        add    = function(veh, plate) return exports['0r-vehiclekeys']:GiveKeys(plate) end,
        remove = function(veh, plate) return exports['0r-vehiclekeys']:RemoveKeys(plate) end,
    },

    ['MrNewbVehicleKeys'] = {
        add    = function(veh, plate) return exports.MrNewbVehicleKeys:GiveKeys(veh) end,
        remove = function(veh, plate) return exports.MrNewbVehicleKeys:RemoveKeys(veh) end,
    },

    ['Renewed-Vehiclekeys'] = {
        add    = function(veh, plate) exports['Renewed-Vehiclekeys']:addKey(plate) return true end,
        remove = function(veh, plate) return exports['Renewed-Vehiclekeys']:removeKey(plate) end,
    },

    ['brutal_keys'] = {
        add    = function(veh, plate) return exports.brutal_keys:addVehicleKey(plate, plate) end,
        remove = function(veh, plate) return exports.brutal_keys:removeKey(plate, true) end,
    },

    ['mk_vehiclekeys'] = {
        add    = function(veh, plate) return exports['mk_vehiclekeys']:AddKey(veh) end,
        remove = function(veh, plate) return exports['mk_vehiclekeys']:RemoveKey(veh) end,
    },

    ['qs-vehiclekeys'] = {
        add = function(veh, plate)
            return exports['qs-vehiclekeys']:GiveKeys(plate, GetDisplayNameFromVehicleModel(GetEntityModel(veh)), true)
        end,
        remove = function(veh, plate)
            return exports['qs-vehiclekeys']:RemoveKeys(plate, GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
        end,
    },

    ['tgiann-hotwire'] = {
        add = function(veh, plate) return exports['tgiann-hotwire']:GiveKeyVehicle(veh, true) end,
    },

    ['wasabi_carlock'] = {
        add    = function(veh, plate) return exports.wasabi_carlock:GiveKey(plate) end,
        remove = function(veh, plate) return exports.wasabi_carlock:RemoveKey(plate) end,
    },

    ['F_RealCarKeysSystem'] = {
        add = function(veh, plate) TriggerServerEvent('F_RealCarKeysSystem:generateVehicleKeys', plate) return true end,
    },

    ['bhd_garage'] = {
        add    = function(veh, plate) TriggerServerEvent('bhd_garage:keys:CreateKey', plate) return true end,
        remove = function(veh, plate) TriggerServerEvent('bhd_garage:keys:DeleteKey', 1, plate) return true end,
    },

    ['mono_carkeys'] = {
        add    = function(veh, plate) TriggerServerEvent('mono_carkeys:CreateKey', plate) return true end,
        remove = function(veh, plate) TriggerServerEvent('mono_carkeys:DeleteKey', 1, plate) return true end,
    },

    ['p_carkeys'] = {
        add    = function(veh, plate) TriggerServerEvent('p_carkeys:CreateKeys', plate) return true end,
        remove = function(veh, plate) TriggerServerEvent('p_carkeys:RemoveKeys', plate) return true end,
    },

    ['p_vehiclekeys'] = {
        add    = function(veh, plate) return exports['p_vehiclekeys']:createKey(plate, veh) end,
        remove = function(veh, plate) return exports['p_vehiclekeys']:removeKey(plate, veh) end,
    },

    ['qb-vehiclekeys'] = {
        add = function(veh, plate)
            return viaServer("add", veh, function()
                TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)

                return true
            end)
        end,
        -- The plate request to take a key back matches far more than one car.
        remove = function(veh, plate)
            return viaServer("remove", veh, function() return false end)
        end,
    },

    ['vehicles_keys'] = {
        add    = function(veh, plate) TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate) return true end,
        remove = function(veh, plate) TriggerServerEvent('vehicles_keys:selfRemoveKeys', plate) return true end,
    },

    ['cd_garage'] = {
        add    = function(veh, plate) TriggerEvent('cd_garage:AddKeys', plate) return true end,
        remove = function(veh, plate) TriggerEvent('cd_garage:RemoveKeys', plate) return true end,
    },

    ['okokGarage'] = {
        add    = function(veh, plate) TriggerServerEvent('okokGarage:GiveKeys', plate) return true end,
        remove = function(veh, plate) TriggerServerEvent('okokGarage:RemoveKeys', plate, GetPlayerServerId(PlayerId())) return true end,
    },
}

providers['qbx_vehiclekeys'] = providers['qb-vehiclekeys']

return function(resource)
    local provider = providers[resource]

    if not provider then return false end

    gg.keys = gg.keys or {}

    gg.keys.AddKeys = function(veh)
        if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return false end

        return provider.add(veh, GetVehicleNumberPlateText(veh))
    end

    gg.keys.RemoveKeys = function(veh)
        if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return false end
        if not provider.remove then return false end

        return provider.remove(veh, GetVehicleNumberPlateText(veh))
    end

    return true
end

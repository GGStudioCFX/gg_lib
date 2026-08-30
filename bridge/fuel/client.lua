local providers = {
    ['ox_fuel'] = {
        get = function(veh) return Entity(veh).state.fuel end,
        set = function(veh, level) Entity(veh).state.fuel = level return true end,
    },

    ['rcore_fuel'] = {
        get = function(veh) return exports['rcore_fuel']:GetVehicleFuelLiters(veh) end,
        set = function(veh, level) return exports['rcore_fuel']:SetVehicleFuel(veh, level) end,
    },

    ['ti_fuel'] = {
        get = function(veh) return exports['ti_fuel']:getFuel(veh) end,
        set = function(veh, level) return exports['ti_fuel']:setFuel(veh, level, "RON91") end,
    },
}

local EXPORT_NAME = {
    ['bigDaddy-Fuel'] = 'BigDaddy-Fuel',
}

for _, resource in ipairs({
    'LegacyFuel',
    'Renewed-Fuel',
    'bigDaddy-Fuel',
    'cdn-fuel',
    'esx-sna-fuel',
    'frkn-fuelstationv4',
    'lc_fuel',
    'okokGasStation',
    'ps-fuel',
    'qb-fuel',
    'qs-fuelstations',
    'x-fuel',
}) do
    local export = EXPORT_NAME[resource] or resource

    providers[resource] = {
        get = function(veh) return exports[export]:GetFuel(veh) end,
        set = function(veh, level) return exports[export]:SetFuel(veh, level) end,
    }
end

return function(resource)
    local provider = providers[resource]

    if not provider then return false end

    gg.fuel = gg.fuel or {}

    gg.fuel.getFuel = function(veh)
        if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return nil end

        return provider.get(veh)
    end

    gg.fuel.setFuel = function(veh, level)
        if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return false end
        if type(level) ~= "number" then level = 100.0 end

        return provider.set(veh, level)
    end

    return true
end

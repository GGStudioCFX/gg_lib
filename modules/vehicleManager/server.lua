gg.vehicleManager = gg.vehicleManager or {}

local EXISTS_TIMEOUT_MS = 5000

local PROPS_BAG = "gg_props"

-- Cars this resource put in the world, so a client naming one by net id can be
-- told apart from one naming any car on the server.
local spawned = {}

gg.vehicleManager.spawnedHere = function(entity)
    if type(entity) ~= "number" or entity == 0 or not spawned[entity] then return false end

    if not DoesEntityExist(entity) then
        spawned[entity] = nil

        return false
    end

    return true
end

gg.vehicleManager.spawnVehicle = function(model, coords, options)
    local hash = type(model) == "string" and GetHashKey(model) or model

    if not hash then return nil, "no vehicle model" end
    if not coords then return nil, "no spawn point" end

    coords = type(coords) == "table" and vec4(coords.x, coords.y, coords.z, coords.w or 0.0) or coords

    local vehicle = gg.cleanup.track(CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, true, true))

    local waited = 0

    while not DoesEntityExist(vehicle) do
        if waited >= EXISTS_TIMEOUT_MS then
            return nil, ("%s would not spawn"):format(tostring(model))
        end

        Wait(0)
        waited = waited + 1
    end

    spawned[vehicle] = true

    if type(options) == "table" then
        local look = {}

        if type(options.properties) == "table" then
            for key, value in pairs(options.properties) do look[key] = value end
        end

        if type(options.plate) == "string" and options.plate ~= "" then
            look.plate = options.plate
        end

        local fuel = tonumber(options.fuel)

        if fuel then look.fuelLevel = fuel + 0.0 end

        if next(look) and lib and lib.setVehicleProperties then
            pcall(lib.setVehicleProperties, vehicle, look)
        end

        if type(options.props) == "table" and type(options.props.list) == "table" and options.props.list[1] then
            Entity(vehicle).state:set(PROPS_BAG, options.props, true)
        end
    end

    return NetworkGetNetworkIdFromEntity(vehicle)
end

gg.vehicleManager.dressVehicle = function(netid, options)
    local entity = NetworkGetEntityFromNetworkId(netid or 0)

    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if type(options) ~= "table" then return false end

    if type(options.properties) == "table" and lib and lib.setVehicleProperties then
        pcall(lib.setVehicleProperties, entity, options.properties)
    end

    if options.props ~= nil then
        Entity(entity).state:set(PROPS_BAG, options.props or false, true)
    end

    return true
end

gg.vehicleManager.removeVehicle = function(netid)
    local entity = NetworkGetEntityFromNetworkId(netid)
    if not netid or type(entity) ~= "number" or entity == 0 then
        return false
    end

    spawned[entity] = nil

    if GetResourceState("AdvancedParking") == "started" then
            exports["AdvancedParking"]:DeleteVehicle(entity, false)
        return true
    end

    if not DoesEntityExist(entity) then
        return false
    end

    DeleteEntity(entity)
    return not DoesEntityExist(entity)
end

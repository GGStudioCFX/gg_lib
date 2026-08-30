gg.vehicleManager = gg.vehicleManager or {}

gg.vehicleManager.spawnVehicle = function(model, cb, coords, isnetworked, teleportInto)
    model = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(model) then return end
    if not coords then return end

    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    isnetworked = isnetworked == nil or isnetworked

    gg.util.loadModel(model)

    local veh = gg.cleanup.track(CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, true, true))

    SetModelAsNoLongerNeeded(model)

    if teleportInto then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end

    if cb then cb(veh) end
end

gg.vehicleManager.removeVehicle = function(entity)
    gg.cleanup.forget(entity)

    if (GetResourceState("AdvancedParking") == "started") then
            exports["AdvancedParking"]:DeleteVehicle(entity)
        return true
    end

    NetworkRequestControlOfEntity(entity)
    local timeout = 2000
    while timeout > 0 and not NetworkHasControlOfEntity(entity) do
        Wait(100)
        timeout = timeout - 100
    end
    SetEntityAsMissionEntity(entity, true, true)
    local timeout = 2000
    while timeout > 0 and not IsEntityAMissionEntity(entity) do
        Wait(100)
        timeout = timeout - 100
    end
    Citizen.InvokeNative( 0xEA386986E786A54F, Citizen.PointerValueIntInitialized( entity ) )
    if ( DoesEntityExist( entity ) ) then 
        DeleteEntity(entity)
        if ( DoesEntityExist( entity ) ) then     
            return false
        else 
            return true
        end
    else 
        return true
    end 
end

function string.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

gg.vehicleManager.GetAllVehicles = function()
    local vehicles = {}
    local vehicleHandle = FindFirstVehicle()
    local success, vehicle = FindNextVehicle(vehicleHandle)
    
    while success do
        table.insert(vehicles, vehicle)
        success, vehicle = FindNextVehicle(vehicleHandle)
    end
    EndFindVehicle(vehicleHandle)
    
    return vehicles
end

gg.vehicleManager.getVehicleByPlate = function(plate)
    if not plate then return false end
    local vehicles = gg.vehicleManager.GetAllVehicles()
    for _, vehicle in ipairs(vehicles) do
        local vehiclePlate = GetVehicleNumberPlateText(vehicle)
        if vehiclePlate and string.trim(vehiclePlate) == string.trim(plate) then
            return vehicle
        end
    end
    return nil
end


local MODEL_TIMEOUT = 5000

local RESOURCE = GetCurrentResourceName()

local keysReady = false

local function ensureKeys()
    if keysReady then return end

    keysReady = true

    local source = LoadResourceFile(RESOURCE, "modules/miniBridge/client.lua")
    if not source then return end

    local chunk = load(source, ("@@%s/modules/miniBridge/client.lua"):format(RESOURCE), "t")
    if chunk then pcall(chunk) end
end

local function requestModel(model)
    local hash = type(model) == "number" and model or joaat(model)

    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + MODEL_TIMEOUT

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    return hash
end

local function spawnPoint(ped)
    local current = GetVehiclePedIsIn(ped, false)

    if current ~= 0 then
        local coords  = GetEntityCoords(current)
        local heading = GetEntityHeading(current)

        return coords, heading, current
    end

    return GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0), GetEntityHeading(ped) + 90.0, nil
end

local function removeVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)

    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

local function spawn(model)
    ensureKeys()

    local ped = PlayerPedId()

    local coords, heading, replacing = spawnPoint(ped)

    local hash = requestModel(model)
    if not hash then return false, ("'%s' is not a vehicle model this client has"):format(tostring(model)) end

    removeVehicle(replacing)

    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)

    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then return false, "the vehicle could not be created" end

    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehRadioStation(vehicle, "OFF")
    SetEntityAsMissionEntity(vehicle, true, true)

    SetPedIntoVehicle(ped, vehicle, -1)

    if gg and gg.keys and gg.keys.AddKeys then pcall(gg.keys.AddKeys, vehicle) end

    return true
end

RegisterNUICallback("catalogue_fetch", function(data, cb)
    local ok, payload = GGCallback.await("gg_lib:catalogue:fetch", {
        refresh = data and data.refresh == true,
    })

    cb({
        ok        = ok == true,
        ITEMS     = ok and payload.items or nil,
        VEHICLES  = ok and payload.vehicles or nil,
        CAN_GIVE  = ok and payload.can_give == true or false,
        IMAGE_URL = ok and payload.image_url or nil,
        WIRED     = ok and payload.wired or nil,
    })
end)

RegisterNUICallback("catalogue_set_image_url", function(data, cb)
    local ok, problem = GGCallback.await("gg_lib:catalogue:setImageUrl", {
        pattern = data and data.pattern,
    })

    cb({ ok = ok == true, error = not ok and problem or nil })
end)

RegisterNUICallback("catalogue_give_item", function(data, cb)
    local ok, problem = GGCallback.await("gg_lib:catalogue:giveItem", {
        item  = data and data.item,
        count = data and data.count,
    })

    cb({ ok = ok == true, error = not ok and problem or nil })
end)

RegisterNUICallback("catalogue_spawn_vehicle", function(data, cb)
    local model = data and data.model

    local allowed, problem = GGCallback.await("gg_lib:catalogue:spawnVehicle", { model = model })

    if not allowed then
        cb({ ok = false, error = problem })
        return
    end

    CreateThread(function()
        local ok, failure = spawn(model)

        cb({ ok = ok == true, error = not ok and failure or nil })
    end)
end)

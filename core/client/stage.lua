
GG_EDITOR_STAGE = GG_EDITOR_STAGE or {}

GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }
GG_EDITOR_BUCKET.enter = GG_EDITOR_BUCKET.enter or function() return false end
GG_EDITOR_BUCKET.leave = GG_EDITOR_BUCKET.leave or function() end

GG_EDITOR_STAGE.PARK = vector3(0.0, 0.0, 1000.0)

local LOAD_TIMEOUT_MS = 8000

local active = false
local home = nil -- where the ped was before it was borrowed

local function drawBubble()
    CreateThread(function()
        local park = GG_EDITOR_STAGE.PARK

        while active do
            DrawMarker(
                28,
                park.x, park.y, park.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                28.0, 28.0, 28.0,
                12, 14, 18, 255,
                false, false, 2, false, nil, nil, false
            )

            Wait(0)
        end
    end)
end

function GG_EDITOR_STAGE.enter()
    if active then return end

    active = true

    GG_EDITOR_BUCKET.enter()

    local ped = PlayerPedId()
    local park = GG_EDITOR_STAGE.PARK

    home = GetEntityCoords(ped)

    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, park.x, park.y, park.z, false, false, false, true)
    SetEntityHeading(ped, 0.0)
    SetEntityRotation(ped, 0.0, 0.0, 0.0, 2, true)

    drawBubble()
end

function GG_EDITOR_STAGE.leave()
    if not active then return end

    active = false

    local ped = PlayerPedId()

    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)

    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)

    if home then
        SetEntityCoords(ped, home.x, home.y, home.z, false, false, false, true)

        home = nil
    end

    GG_EDITOR_BUCKET.leave()
end

function GG_EDITOR_STAGE.active()
    return active
end

function GG_EDITOR_STAGE.spawn(model, heading)
    if type(model) ~= "string" or model == "" then
        return nil, "no vehicle model"
    end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) then
        return nil, ("vehicle model '%s' is not in the game"):format(model)
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            return nil, ("vehicle model '%s' would not load"):format(model)
        end

        Wait(0)
    end

    if not IsModelAVehicle(hash) then
        SetModelAsNoLongerNeeded(hash)

        return nil, ("model '%s' is not a vehicle"):format(model)
    end

    local ped = PlayerPedId()
    local at = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.5, 0.0)

    local vehicle = CreateVehicle(hash, at.x, at.y, at.z, heading or 90.0, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not (vehicle and DoesEntityExist(vehicle)) then
        return nil, ("%s would not spawn"):format(model)
    end

    SetEntityInvincible(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 2)
    SetVehicleDirtLevel(vehicle, 0.0)

    FreezeEntityPosition(vehicle, true)

    SetVehicleModKit(vehicle, 0)

    return vehicle
end

function GG_EDITOR_STAGE.ride(vehicle)
    if not (vehicle and DoesEntityExist(vehicle)) then return false end

    local ped = PlayerPedId()

    FreezeEntityPosition(ped, false)

    local taken = false

    for _, seat in ipairs({ 0, 1, 2 }) do
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(ped, vehicle, seat)

            taken = true
            break
        end
    end

    if not taken then SetPedIntoVehicle(ped, vehicle, -1) end

    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)

    return true
end

function GG_EDITOR_STAGE.despawn(vehicle)
    if vehicle and DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
end

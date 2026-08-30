gg.blip = gg.blip or {}

local activeBlips = {}
local blipCounter = 1
local Waypoints = {}

gg.blip.createBlip = function(data)
        local id = blipCounter
        if activeBlips[id] then
            while not activeBlips[id] do
                blipCounter = blipCounter + 1
                id = blipCounter
                Wait(10)
            end
        end
        activeBlips[id] = gg.cleanup.track(AddBlipForCoord(data.coords), "blip")
        SetBlipAsShortRange(activeBlips[id], true)
        SetBlipSprite(activeBlips[id], data.sprite)
        SetBlipColour(activeBlips[id], data.color or 1)
        SetBlipScale(activeBlips[id], data.scale or 0.7)
        SetBlipDisplay(activeBlips[id], (data.disp or 6))
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(tostring(data.name))
        EndTextCommandSetBlipName(activeBlips[id])
    return id
end

gg.blip.createRadiusBlip = function(data, b_id)
    local id = b_id
    if activeBlips[id] then
        while not activeBlips[id] do
            blipCounter = blipCounter + 1
            id = blipCounter
            Wait(10)
        end
    end
    activeBlips[id] = gg.cleanup.track(AddBlipForRadius(data.coords.x, data.coords.y, data.coords.z or 0.0, data.radius), "blip")

    SetBlipColour(activeBlips[id], data.color or 5)
    SetBlipAlpha(activeBlips[id], 150) -- must be 0–255 int, not 0.0–1.0
    return id
end

gg.blip.createFadingBlip = function(data, duration)
        local id = blipCounter
        activeBlips[id] = gg.cleanup.track(AddBlipForCoord(data.coords), "blip")
        SetBlipAsShortRange(blip, true)
        SetBlipSprite(blip, data.sprite or 106)
        SetBlipColour(blip, data.color or 5)
        SetBlipScale(blip, data.scale or 0.7)
        SetBlipDisplay(blip, (data.disp or 6))
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(tostring(data.name))
        EndTextCommandSetBlipName(blip)
        blipCounter += 1
    return id
end

gg.blip.createVehicleBlip = function(veh, data)
    local id = data.id
    activeBlips[id] = gg.cleanup.track(AddBlipForEntity(veh), "blip")
    SetBlipAsShortRange(activeBlips[id], true)
    SetBlipSprite(activeBlips[id], data.sprite)
    SetBlipColour(activeBlips[id], data.color or 1)
    SetBlipScale(activeBlips[id], data.scale or 0.7)
    SetBlipDisplay(activeBlips[id], data.display or 6)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(data.name))
    EndTextCommandSetBlipName(activeBlips[id])
    return id
end

gg.blip.deleteBlip = function(id)
        if activeBlips[id] then
            gg.cleanup.forget(activeBlips[id], "blip")

            RemoveBlip(activeBlips[id])
            activeBlips[id] = nil
        end
    return false
end

gg.blip.CreateWaypoint = function(id, coords, color, name)
    if Waypoints[id] then
        return false
    end

    Waypoints[id] = gg.cleanup.track(AddBlipForCoord(coords.x, coords.y, coords.z), "blip")
    SetBlipColour(Waypoints[id], color.blip_color)
    SetBlipRoute(Waypoints[id], true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(tostring(name or ""))
    EndTextCommandSetBlipName(Waypoints[id])
    SetBlipRouteColour(Waypoints[id], color.route_color)

    return true
end

gg.blip.DeleteWaypoint = function(id)
    if not Waypoints[id] then
        return false
    end

    gg.cleanup.forget(Waypoints[id], "blip")

    RemoveBlip(Waypoints[id] )
    Waypoints[id]  = nil

    return true
end

gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local coords = data.coords or vector3(0.0, 0.0, 0.0)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)

    local payload = {
        title = data.message,
        code = data.code,
        description = data.message,
        location = streetName,
        sound = "dispatch",
        x = coords.x,
        y = coords.y,
        z = coords.z,
        type = data.priority == 1 and "Alert" or "Call",
        weapon = data.weapon and {
            name = data.weapon
        } or nil,
        blip = data.blipData and {
            radius = data.blipData.radius or 0.0,
            sprite = data.blipData.sprite,
            color = data.blipData.color,
            scale = data.blipData.scale,
            length = math.floor((data.time or 60000) / 60000)
        } or nil,
        jobs = data.jobs
    }

    TriggerEvent('kartik-mdt:server:sendDispatchNotification', payload)
end

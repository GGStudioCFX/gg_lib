gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local playerData = exports['rcore_dispatch']:GetPlayerData()
    local alertData = {
        code = data.code or '10-00',
        default_priority = (data.priority == 1 and 'high') or (data.priority == 2 and 'medium') or 'low',
        coords = data.coords or playerData.coords,
        job = data.jobs or 'police',
        text = data.message or 'Dispatch Alert',
        type = 'alerts',
        blip_time = data.time and (data.time / 1000) or 5,
        blip = {
            sprite = data.blipData and data.blipData.sprite or 54,
            colour = data.blipData and data.blipData.color or 3,
            scale = data.blipData and data.blipData.scale or 0.7,
            text = data.message or 'Dispatch Alert',
            flashes = data.blipData and data.blipData.flash or false,
            radius = data.blipData and data.blipData.radius or 0,
        }
    }

    TriggerServerEvent('rcore_dispatch:server:sendAlert', alertData)
end

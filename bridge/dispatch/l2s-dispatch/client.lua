gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local playerData = exports['l2s-dispatch']:GetPlayerData()
    TriggerServerEvent('l2s-dispatch:server:AddNotification', {
        departments = data.jobs or {'POLICE'},
        title = data.code or '10-80',
        message = data.message or '',
        coords = vec2((data.coords or GetEntityCoords(PlayerPedId())).x, (data.coords or GetEntityCoords(PlayerPedId())).y),
        priority = data.priority or 1,
        sound = 1,
        street = playerData.street,
        reply = playerData.source,
        anonymous = false,
        blip = {
            sprite = data.blipData and data.blipData.sprite or 1,
            colour = data.blipData and data.blipData.color or 1,
            scale = data.blipData and data.blipData.scale or 1.0,
            text = (data.code or '') .. ' - ' .. (data.message or 'Alert'),
        },
        info = {
            { icon = data.icon or 'info', text = data.message or 'Dispatch Alert' },
            { icon = 'person', text = playerData.sex },
            data.plate and { icon = 'car', text = data.plate } or nil,
        }
    })
end

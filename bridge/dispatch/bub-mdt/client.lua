gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local coords = data.coords or GetEntityCoords(PlayerPedId())

    exports["bub-mdt"]:CustomAlert({
        code        = data.code or '10-80',
        offense     = data.message or "No message provided",
        coords      = coords,
        info        = { label = data.code or '10-80', icon = data.icon or 'fas fa-question' },
        blip        = data.blipData and data.blipData.sprite or 1,
        isEmergency = data.priority == 1,
        blipCoords  = coords,
    })
end

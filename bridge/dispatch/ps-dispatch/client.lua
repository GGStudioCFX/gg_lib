gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local payload = {
        message = data.message or "No message provided",
        code = data.code or '10-80',
        icon = data.icon or 'fas fa-question',
        priority = data.priority or 2,
        coords = data.coords or GetEntityCoords(PlayerPedId()),
        vehicle = data.vehicle,
        plate = data.plate,
        alertTime = data.time and (data.time / 1000) or nil,
        radius = data.blipData and data.blipData.radius or 0,
        sprite = data.blipData and data.blipData.sprite or 161,
        color = data.blipData and data.blipData.color or 84,
        scale = data.blipData and data.blipData.scale or 1.0,
        length = (data.blipData and data.blipData.length and ((data.blipData.length / 1000) / 60)) or 0.5,
        sound = "Lose_1st",
        sound2 = "GTAO_FM_Events_Soundset",
        offset = false,
        flash = data.blipData and data.blipData.flash or false,
        jobs = data.jobs or data.job or "police"
    }
    exports["ps-dispatch"]:CustomAlert(payload)
end

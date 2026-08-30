gg.dispatch = gg.dispatch or {}

RegisterNetEvent(GetCurrentResourceName() .. ":server:piotreq_gpt:alert", function(data)
    exports['piotreq_gpt']:SendAlert(source, {
        title = data.message or "No message provided",
        code = data.code or '10-80',
        icon = data.icon or 'fa-solid fa-question',
        info = {
            { icon = 'fa-solid fa-road', isStreet = true },
            { icon = data.icon or 'fa-solid fa-question', data = data.message or "No additional info" },
        },
        blip = {
            scale = data.blipData and data.blipData.scale or 1.0,
            sprite = data.blipData and data.blipData.sprite or 161,
            category = 1,
            color = data.blipData and data.blipData.color or 84,
            hidden = false,
            priority = data.priority or 5,
            short = true,
            alpha = 200,
            name = data.message or "Dispatch Alert",
        },
        type = 'normal',
        canAnswer = false,
        maxOfficers = 6,
        time = (data.time and math.floor(data.time / 60000)) or 5,
        notifyTime = 8000,
    })
end)

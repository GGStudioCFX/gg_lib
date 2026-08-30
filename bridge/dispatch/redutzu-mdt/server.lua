gg.dispatch = gg.dispatch or {}

RegisterNetEvent(GetCurrentResourceName() .. ":server:redutzu-mdt:alert", function(data)
    TriggerEvent('redutzu-mdt:server:addDispatchToMDT', {
        code = data.code,
        title = data.message,
        street = data.street,
        duration = data.time,
        coords = data.coords
    })
end)

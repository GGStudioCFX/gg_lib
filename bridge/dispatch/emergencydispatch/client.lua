gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local jobs = data.jobs or {}

    TriggerServerEvent('emergencydispatch:emergencycall:new',
        data.job or jobs[1] or "police",
        data.message or "No message provided",
        data.coords or GetEntityCoords(PlayerPedId()),
        true)
end

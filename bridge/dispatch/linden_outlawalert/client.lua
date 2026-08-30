gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    TriggerServerEvent('wf-alerts:svNotify', {
        dispatchData = {
            displayCode   = data.code or '10-80',
            description   = data.message or "No message provided",
            isImportant   = data.priority == 1 and 1 or 0,
            recipientList = data.jobs or { data.job or "police" },
            length        = data.time or 10000,
            infoM         = data.icon or 'fas fa-question',
            info          = data.message or "No message provided",
        },
        caller = data.caller or 'Anonymous',
        coords = data.coords or GetEntityCoords(PlayerPedId()),
    })
end

gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    TriggerServerEvent(GetCurrentResourceName() .. ":server:piotreq_gpt:alert", data)
end

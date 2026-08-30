gg.dispatch = gg.dispatch or {}

RegisterNetEvent(GetCurrentResourceName() .. ":server:lb-tablet:alert", function(data) exports["lb-tablet"]:AddDispatch(data) end)

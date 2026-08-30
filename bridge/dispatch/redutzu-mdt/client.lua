gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local streetHash, crossingHash = GetStreetNameAtCoord(data.coords.x, data.coords.y, data.coords.z)
    local streetName = GetStreetNameFromHashKey(streetHash)
    local payload = {
        code = data.code or '10-80',
        message = data.message or "Dispatch Alert",
        street = streetName,
        time = data.time or 10000,
        coords = data.coords,
    }
    TriggerServerEvent(GetCurrentResourceName() .. ":server:redutzu-mdt:alert", payload)
end

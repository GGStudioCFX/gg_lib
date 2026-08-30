gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local coords = data.coords or GetEntityCoords(PlayerPedId())

    exports.wasabi_mdt:CreateDispatch({
        type        = data.code or '10-80',
        title       = data.code or '10-80',
        description = data.message or "No message provided",
        location    = { coords.x, coords.y, coords.z },
        coords      = { coords.x, coords.y, coords.z },
    })
end

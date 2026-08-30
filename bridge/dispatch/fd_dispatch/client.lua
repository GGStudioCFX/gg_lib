gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local coords = data.coords or GetEntityCoords(PlayerPedId())

    local metadata = {}

    if data.vehicle then
        metadata[#metadata + 1] = {
            type  = 'vehicle',
            model = data.vehicle,
            plate = data.plate,
            color = data.colorHex,
        }
    end

    exports["fd_dispatch"]:CustomAlert({
        title       = data.message or "No message provided",
        description = data.message or "",
        groups      = data.jobs or data.job or "police",
        location    = {
            coords = coords,
            street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)),
        },
        code     = data.code or '10-80',
        priority = data.priority or 2,
        metadata = metadata,
        blip = {
            radius = data.blipData and data.blipData.radius or 0,
            sprite = data.blipData and data.blipData.sprite or 161,
            color  = data.blipData and data.blipData.color or 84,
            scale  = data.blipData and data.blipData.scale or 1.0,
            time   = data.time and (data.time / 1000) or nil,
        },
    })
end

-- 1.0.31 Studio helpers: a coords field's Use My Position, and what a list's rows say live.

-- Where the player stands (their car's spot when they drive one) and which way they face,
-- at once: no camera, no gizmo. The height is the ped's centre, as the position picker's
-- own ped stands; a prop's spot (ground = true) is the ground under them.
RegisterNUICallback("settings_coords_here", function(data, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity  = vehicle ~= 0 and vehicle or ped
    local coords  = GetEntityCoords(entity)
    local z       = coords.z

    if type(data) == "table" and data.ground == true and vehicle == 0 then
        z = z - GetEntityHeightAboveGround(ped)
    end

    cb({
        ok = true,
        COORDS = {
            x = math.floor(coords.x * 100 + 0.5) / 100,
            y = math.floor(coords.y * 100 + 0.5) / 100,
            z = math.floor(z * 100 + 0.5) / 100,
            heading = math.floor((GetEntityHeading(entity) % 360) * 100 + 0.5) / 100,
        },
    })
end)

-- What each row of a list says on its line (a dot, a short count), from the script
-- (settings.rowStatus), for the rows as the editor holds them.
RegisterNUICallback("settings_row_status", function(data, cb)
    if type(data) ~= "table" or type(data.resource) ~= "string" or type(data.path) ~= "string" then
        cb({ ok = false })
        return
    end

    -- A server that does not answer in time throws; the page then just keeps its last line.
    local asked, ok, status = pcall(GGCallback.await, "gg_lib:settings:row_status", {
        resource = data.resource,
        path     = data.path,
        rows     = type(data.rows) == "table" and data.rows or nil,
    })

    ok = asked and ok == true

    cb({ ok = ok, STATUS = ok and status or nil })
end)

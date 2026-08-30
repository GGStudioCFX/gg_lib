gg.waypoint = gg.waypoint or {}

function gg.waypoint.create(data)
    return exports.gg_lib:ggWaypointCreate(data) == true
end

function gg.waypoint.update(id, data)
    return exports.gg_lib:ggWaypointUpdate(id, data) == true
end

function gg.waypoint.remove(id)
    return exports.gg_lib:ggWaypointRemove(id) == true
end

function gg.waypoint.exists(id)
    return exports.gg_lib:ggWaypointExists(id) == true
end

function gg.waypoint.show(id)
    return exports.gg_lib:ggWaypointShow(id) == true
end

function gg.waypoint.hide(id)
    return exports.gg_lib:ggWaypointHide(id) == true
end

function gg.waypoint.clear()
    return exports.gg_lib:ggWaypointClear() == true
end

function gg.waypoint.setRoutePoint(routeId, index, coords, options)
    return exports.gg_lib:ggWaypointSetRoutePoint(routeId, index, coords, options) == true
end

function gg.waypoint.activeRoutePoint(routeId)
    return exports.gg_lib:ggWaypointActiveRoutePoint(routeId)
end

function gg.waypoint.clearRoute(routeId)
    return exports.gg_lib:ggWaypointClearRoute(routeId) == true
end

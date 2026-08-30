gg.zones = gg.zones or {}

local tracked = setmetatable({}, { __mode = "k" })

local function wanted()
    return gg.debug.on()
end

local function live(zone)
    local all = lib.zones.getAllZones and lib.zones.getAllZones()

    return not all or all[zone.id] == zone
end

local function paint(zone, on)
    if type(zone) ~= "table" or not zone.setDebug then return end

    if on ~= true and not zone.debug then return end

    pcall(zone.setDebug, zone, on == true)

    if on ~= true or not zone.insideZone then return end

    local current = lib.zones.getCurrentZones and lib.zones.getCurrentZones()

    if current then current[zone.id] = zone end
end

local function track(zone)
    if type(zone) ~= "table" then return zone end

    -- zone.remove is deliberately left alone: the zone tick filters on that
    -- function by identity, so wrapping it drops the zone out of the tick.
    tracked[zone] = true

    return zone
end

function gg.zones.refresh()
    local on = wanted()

    for zone in pairs(tracked) do
        if live(zone) then
            paint(zone, on)
        else
            tracked[zone] = nil
        end
    end
end

local function build(kind, data)
    if type(data) ~= "table" then return nil end

    data.debug = wanted() or nil

    local zone = lib.zones[kind](data)

    paint(zone, wanted())

    return track(zone)
end

function gg.zones.poly(data)
    return build("poly", data)
end

function gg.zones.box(data)
    return build("box", data)
end

function gg.zones.sphere(data)
    return build("sphere", data)
end

if settings then
    if settings.onChange then settings.onChange(gg.zones.refresh) end
    if settings.generic and settings.generic.onChange then settings.generic.onChange(gg.zones.refresh) end
end

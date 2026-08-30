gg.target = gg.target or {}

local function unpackOptions(parameters)
    if type(parameters) ~= "table" then return {}, nil end

    if parameters.options then return parameters.options, parameters.distance end

    return parameters, parameters.distance
end

local function toProvider(parameters)
    local options, distance = unpackOptions(parameters)
    local out = { options = {}, distance = distance }

    for index = 1, #options do
        local option = options[index]

        out.options[index] = {
            label       = option.label or option.name,
            icon        = option.icon,
            item        = option.item or option.items,
            job         = option.job or option.groups,
            gang        = option.gang,
            distance    = option.distance,
            canInteract = option.canInteract,
            action      = option.action or option.onSelect,
            event       = option.event,
            serverEvent = option.serverEvent,
            command     = option.command,
            type        = option.type,
        }
    end

    return out
end

local function labelsOf(parameters)
    local options = unpackOptions(parameters)
    local labels = {}

    for index = 1, #options do
        labels[index] = options[index].label or options[index].name
    end

    return labels
end

local function asLabels(value)
    if type(value) == "table" and (value.options or (value[1] and type(value[1]) == "table")) then
        return labelsOf(value)
    end

    return value
end

local owned = {}

local function remember(kind, key, extra)
    local resource = GetInvokingResource() or GetCurrentResourceName()

    owned[#owned + 1] = { kind = kind, key = key, extra = extra, resource = resource }
end

local function forget(kind, key)
    for index = #owned, 1, -1 do
        local entry = owned[index]

        if entry.kind == kind and entry.key == key then table.remove(owned, index) end
    end
end

AddEventHandler("onClientResourceStop", function(resource)
    for index = #owned, 1, -1 do
        local entry = owned[index]

        if entry.resource == resource then
            if entry.kind == "zone" then
                exports["qb-target"]:RemoveZone(entry.key)
            elseif entry.kind == "entity" then
                if DoesEntityExist(entry.key) then
                    exports["qb-target"]:RemoveTargetEntity(entry.key, entry.extra)
                end
            elseif entry.kind == "model" then
                exports["qb-target"]:RemoveTargetModel(entry.key, entry.extra)
            elseif entry.kind == "global" then
                exports["qb-target"]:RemoveGlobalType(entry.key, entry.extra)
            end

            table.remove(owned, index)
        end
    end
end)

gg.target.addEntity = function(entity, parameters)
    if not entity or not DoesEntityExist(entity) then return false end

    exports["qb-target"]:AddTargetEntity(entity, toProvider(parameters))
    remember("entity", entity, labelsOf(parameters))

    return true
end

gg.target.removeEntity = function(entity, names)
    if not entity then return false end

    exports["qb-target"]:RemoveTargetEntity(entity, asLabels(names))
    forget("entity", entity)

    return true
end

gg.target.addModel = function(models, parameters)
    exports["qb-target"]:AddTargetModel(models, toProvider(parameters))
    remember("model", models, labelsOf(parameters))

    return true
end

gg.target.removeModel = function(models, names)
    exports["qb-target"]:RemoveTargetModel(models, asLabels(names))
    forget("model", models)

    return true
end

local nextZone = 0

local function zoneName(data)
    if type(data.name) == "string" and data.name ~= "" then return data.name end

    nextZone = nextZone + 1

    return ("gg_zone_%s_%d"):format(GetInvokingResource() or GetCurrentResourceName(), nextZone)
end

gg.target.addBoxZone = function(data)
    local name   = zoneName(data)
    local coords = data.coords
    local size   = data.size or vec3(1.0, 1.0, 1.0)

    exports["qb-target"]:AddBoxZone(name, vec3(coords.x, coords.y, coords.z), size.x, size.y, {
        name      = name,
        heading   = data.rotation or coords.w or 0.0,
        debugPoly = data.debug or gg.debug.on(),
        minZ      = coords.z - ((size.z or 2.0) / 2),
        maxZ      = coords.z + ((size.z or 2.0) / 2),
    }, toProvider(data))

    remember("zone", name)

    return name
end

gg.target.addSphereZone = function(data)
    local name   = zoneName(data)
    local coords = data.coords

    exports["qb-target"]:AddCircleZone(name, vec3(coords.x, coords.y, coords.z), data.radius or 1.0, {
        name      = name,
        debugPoly = data.debug or gg.debug.on(),
        useZ      = true,
    }, toProvider(data))

    remember("zone", name)

    return name
end

gg.target.addPolyZone = function(data)
    local name = zoneName(data)

    exports["qb-target"]:AddPolyZone(name, data.points, {
        name      = name,
        debugPoly = data.debug or gg.debug.on(),
        minZ      = data.minZ,
        maxZ      = data.maxZ,
    }, toProvider(data))

    remember("zone", name)

    return name
end

gg.target.removeZone = function(id)
    if id == nil then return false end

    exports["qb-target"]:RemoveZone(id)
    forget("zone", id)

    return true
end

local function globalArgs(first, second)
    if type(first) == "string" then return second end

    return first
end

local function addGlobal(kind, parameters)
    exports["qb-target"]:AddGlobalType(kind, toProvider(parameters))
    remember("global", kind, labelsOf(parameters))
end

gg.target.addGlobalPed = function(first, second)
    addGlobal(1, globalArgs(first, second))

    return true
end

gg.target.removeGlobalPed = function(names)
    exports["qb-target"]:RemoveGlobalType(1, asLabels(names))

    return true
end

gg.target.addGlobalVehicle = function(first, second)
    addGlobal(2, globalArgs(first, second))

    return true
end

gg.target.removeGlobalVehicle = function(names)
    exports["qb-target"]:RemoveGlobalType(2, asLabels(names))

    return true
end

gg.target.addGlobalObject = function(first, second)
    addGlobal(3, globalArgs(first, second))

    return true
end

gg.target.removeGlobalObject = function(names)
    exports["qb-target"]:RemoveGlobalType(3, asLabels(names))

    return true
end

gg.target.addGlobalPlayer = function(first, second)
    addGlobal(4, globalArgs(first, second))

    return true
end

gg.target.removeGlobalPlayer = function(names)
    exports["qb-target"]:RemoveGlobalType(4, asLabels(names))

    return true
end

gg.target.disable = function(state)
    exports["qb-target"]:AllowTargeting(state ~= true)
end

gg.target.isActive = function()
    local ok, active = pcall(function() return exports["qb-target"]:IsTargetActive() end)

    return ok and active == true
end

gg.target.AddTargetEntity    = gg.target.addEntity
gg.target.removeTargetEntity = gg.target.removeEntity
gg.target.RemoveZone         = gg.target.removeZone

gg.target.AddBoxZone = function(name, coords, size, parameters)
    local options, distance = unpackOptions(parameters)

    return gg.target.addBoxZone({
        name     = name,
        coords   = coords,
        size     = size,
        options  = options,
        distance = distance,
    })
end

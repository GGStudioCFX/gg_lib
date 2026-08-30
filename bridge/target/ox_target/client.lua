gg.target = gg.target or {}

local function unpackOptions(parameters)
    if type(parameters) ~= "table" then return {}, nil end

    if parameters.options then return parameters.options, parameters.distance end

    return parameters, parameters.distance
end

local function toProvider(parameters)
    local options, distance = unpackOptions(parameters)
    local out = {}

    for index = 1, #options do
        local option = options[index]

        out[index] = {
            name        = option.name or option.label,
            label       = option.label,
            icon        = option.icon,
            iconColor   = option.iconColor,
            distance    = option.distance or distance,
            items       = option.items or option.item,
            anyItem     = option.anyItem,
            groups      = option.groups or option.job or option.gang,
            bones       = option.bones or option.bone,
            canInteract = option.canInteract,
            onSelect    = option.onSelect or option.action,
            event       = option.event,
            serverEvent = option.serverEvent,
            command     = option.command,
        }
    end

    return out
end

local function namesOf(parameters)
    local options = unpackOptions(parameters)
    local names = {}

    for index = 1, #options do
        names[index] = options[index].name or options[index].label
    end

    return names
end

local function asNames(value)
    if type(value) == "table" and (value.options or value[1] and type(value[1]) == "table") then
        return namesOf(value)
    end

    return value
end

gg.target.addEntity = function(entity, parameters)
    if not entity or not DoesEntityExist(entity) then return false end

    local options = toProvider(parameters)

    if NetworkGetEntityIsNetworked(entity) then
        exports.ox_target:addEntity(NetworkGetNetworkIdFromEntity(entity), options)
    else
        exports.ox_target:addLocalEntity(entity, options)
    end

    return true
end

gg.target.removeEntity = function(entity, names)
    if not entity then return false end

    if DoesEntityExist(entity) and NetworkGetEntityIsNetworked(entity) then
        exports.ox_target:removeEntity(NetworkGetNetworkIdFromEntity(entity), asNames(names))
    else
        exports.ox_target:removeLocalEntity(entity, asNames(names))
    end

    return true
end

gg.target.addModel = function(models, parameters)
    exports.ox_target:addModel(models, toProvider(parameters))

    return true
end

gg.target.removeModel = function(models, names)
    exports.ox_target:removeModel(models, asNames(names))

    return true
end

gg.target.addBoxZone = function(data)
    return exports.ox_target:addBoxZone({
        coords     = data.coords,
        size       = data.size,
        rotation   = data.rotation or (data.coords and data.coords.w) or 0.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.addSphereZone = function(data)
    return exports.ox_target:addSphereZone({
        coords     = data.coords,
        radius     = data.radius or 1.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.addPolyZone = function(data)
    return exports.ox_target:addPolyZone({
        points     = data.points,
        thickness  = data.thickness or 4.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.removeZone = function(id)
    if id == nil then return false end

    exports.ox_target:removeZone(id, true)

    return true
end

local function globalArgs(first, second)
    if type(first) == "string" then return second end

    return first
end

gg.target.addGlobalPed = function(first, second)
    exports.ox_target:addGlobalPed(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalPed = function(names)
    exports.ox_target:removeGlobalPed(asNames(names))

    return true
end

gg.target.addGlobalVehicle = function(first, second)
    exports.ox_target:addGlobalVehicle(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalVehicle = function(names)
    exports.ox_target:removeGlobalVehicle(asNames(names))

    return true
end

gg.target.addGlobalObject = function(first, second)
    exports.ox_target:addGlobalObject(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalObject = function(names)
    exports.ox_target:removeGlobalObject(asNames(names))

    return true
end

gg.target.addGlobalPlayer = function(first, second)
    exports.ox_target:addGlobalPlayer(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalPlayer = function(names)
    exports.ox_target:removeGlobalPlayer(asNames(names))

    return true
end

gg.target.disable = function(state)
    exports.ox_target:disableTargeting(state == true)
end

gg.target.isActive = function()
    local ok, active = pcall(function() return exports.ox_target:isActive() end)

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

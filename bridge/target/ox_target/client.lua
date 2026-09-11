gg.target = gg.target or {}

-- Which resource answers. sleepless_interact and lation_interact answer every
-- ox_target export under their own name, so they run this file with theirs.
local NAME = GG_TARGET_EXPORT or "ox_target"

-- Every line below this calls somebody else's resource. When one of them throws
-- -- a bad release, a renamed export, a breaking change -- the error would
-- otherwise land inside whichever GG script happened to be registering a zone
-- at the time, and read as ours. Nothing gets through here: the call fails
-- quietly, the script keeps running, and the console says whose code broke,
-- once per export, with the line to send them. The counts stay on
-- gg.bridge_status.target, and the print is picked up by the support bundle.
local seen = {}
local wrapped = {}

-- Looking the export up is itself what throws when it does not exist, so the
-- lookup has to happen in here rather than at the call site.
local function invoke(fn, ...)
    return exports[NAME][fn](nil, ...)
end

local function failed(fn, err)
    local status = rawget(gg, "bridge_status")
    status = status and status.target

    if status then
        status.provider_failures = status.provider_failures or {}
        status.provider_failures[fn] = (status.provider_failures[fn] or 0) + 1
    end

    if seen[fn] then return end
    seen[fn] = true

    print(("^1[gg_lib] %s:%s() threw. That is %s's code, not gg_lib's -- send them this:^0\n%s")
        :format(NAME, fn, NAME, tostring(err)))
end

local provider = setmetatable({}, {
    __index = function(_, fn)
        local call = wrapped[fn]

        if not call then
            call = function(_, ...)
                local answer = table.pack(pcall(invoke, fn, ...))

                if answer[1] then return table.unpack(answer, 2, answer.n) end

                failed(fn, answer[2])

                return nil
            end

            wrapped[fn] = call
        end

        return call
    end,
})

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
        for key, value in pairs(option) do
            if out[index][key] == nil then out[index][key] = value end
        end
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
        provider:addEntity(NetworkGetNetworkIdFromEntity(entity), options)
    else
        provider:addLocalEntity(entity, options)
    end

    return true
end

gg.target.removeEntity = function(entity, names)
    if not entity then return false end

    if DoesEntityExist(entity) and NetworkGetEntityIsNetworked(entity) then
        provider:removeEntity(NetworkGetNetworkIdFromEntity(entity), asNames(names))
    else
        provider:removeLocalEntity(entity, asNames(names))
    end

    return true
end

gg.target.addModel = function(models, parameters)
    provider:addModel(models, toProvider(parameters))

    return true
end

gg.target.removeModel = function(models, names)
    provider:removeModel(models, asNames(names))

    return true
end

gg.target.addBoxZone = function(data)
    return provider:addBoxZone({
        name       = data.name,
        coords     = data.coords,
        size       = data.size,
        rotation   = data.rotation or (data.coords and data.coords.w) or 0.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.addSphereZone = function(data)
    return provider:addSphereZone({
        name       = data.name,
        coords     = data.coords,
        radius     = data.radius or 1.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.addPolyZone = function(data)
    return provider:addPolyZone({
        name      = data.name,
        points     = data.points,
        thickness  = data.thickness or 4.0,
        debug      = data.debug or gg.debug.on(),
        drawSprite = data.drawSprite,
        options    = toProvider(data),
    })
end

gg.target.removeZone = function(id)
    if id == nil then return false end

    provider:removeZone(id, true)

    return true
end

local function globalArgs(first, second)
    if type(first) == "string" then return second end

    return first
end

gg.target.addGlobalPed = function(first, second)
    provider:addGlobalPed(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalPed = function(names)
    provider:removeGlobalPed(asNames(names))

    return true
end

gg.target.addGlobalVehicle = function(first, second)
    provider:addGlobalVehicle(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalVehicle = function(names)
    provider:removeGlobalVehicle(asNames(names))

    return true
end

gg.target.addGlobalObject = function(first, second)
    provider:addGlobalObject(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalObject = function(names)
    provider:removeGlobalObject(asNames(names))

    return true
end

gg.target.addGlobalPlayer = function(first, second)
    provider:addGlobalPlayer(toProvider(globalArgs(first, second)))

    return true
end

gg.target.removeGlobalPlayer = function(names)
    provider:removeGlobalPlayer(asNames(names))

    return true
end

gg.target.disable = function(state)
    provider:disableTargeting(state == true)
end

gg.target.isActive = function()
    local ok, active = pcall(function() return provider:isActive() end)

    return ok and active == true
end

gg.target.AddTargetEntity    = gg.target.addEntity
gg.target.removeTargetEntity = gg.target.removeEntity
gg.target.RemoveZone         = gg.target.removeZone

gg.target.AddBoxZone = function(name, coords, size, parameters)
    local options, distance = unpackOptions(parameters)

    return gg.target.addBoxZone({
        name     = name,
        name     = name,
        coords   = coords,
        size     = size,
        options  = options,
        distance = distance,
    })
end

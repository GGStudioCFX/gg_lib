
local BAG = "gg_props"
local DEFAULT_BONE = "chassis"
local LOAD_TIMEOUT_MS = 5000

local fitted = {}

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

local function strip(entity)
    local props = fitted[entity]

    if not props then return end

    for _, prop in ipairs(props) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end

    fitted[entity] = nil
end

local function fit(entity, data)
    strip(entity)

    if not (entity and DoesEntityExist(entity)) then return end
    if type(data) ~= "table" or type(data.list) ~= "table" then return end

    local place = type(data.place) == "table" and data.place or {}
    local bone = GetEntityBoneIndexByName(entity, data.bone or DEFAULT_BONE)

    local base = (data.list[1] and data.list[1].offset) or {}

    local anchor = nil
    local props = {}

    for _, spec in ipairs(data.list) do
        if type(spec) == "table" and type(spec.model) == "string" and spec.model ~= "" then
            local hash = GetHashKey(spec.model)

            if loadModel(hash) then
                local at = GetEntityCoords(entity)
                local prop = CreateObject(hash, at.x, at.y, at.z, false, false, false)

                local offset = spec.offset or {}
                local rotation = spec.rotation or {}

                if not anchor then
                    AttachEntityToEntity(
                        prop, entity, bone,
                        tonumber(place.x) or 0.0, tonumber(place.y) or 0.0, tonumber(place.z) or 0.0,
                        tonumber(place.rx) or 0.0, tonumber(place.ry) or 0.0, tonumber(place.rz) or 0.0,
                        true, true, false, false, 2, true
                    )

                    anchor = prop
                else
                    AttachEntityToEntity(
                        prop, anchor, 0,
                        (tonumber(offset.x) or 0.0) - (tonumber(base.x) or 0.0),
                        (tonumber(offset.y) or 0.0) - (tonumber(base.y) or 0.0),
                        (tonumber(offset.z) or 0.0) - (tonumber(base.z) or 0.0),
                        tonumber(rotation.x) or 0.0,
                        tonumber(rotation.y) or 0.0,
                        tonumber(rotation.z) or 0.0,
                        true, true, false, false, 2, true
                    )
                end

                SetModelAsNoLongerNeeded(hash)

                props[#props + 1] = prop
            end
        end
    end

    if props[1] then fitted[entity] = props end
end

--- Fitting a kit is normally the statebag's job, but the editors work on
--- vehicles that were never networked -- the customs bay spawns its own -- so
--- they dress theirs by hand with the same code rather than a copy of it.
GGAttachments = GGAttachments or {}

GGAttachments.fit = fit
GGAttachments.strip = strip

AddStateBagChangeHandler(BAG, "", function(bagName, _, value)
    CreateThread(function()
        local deadline = GetGameTimer() + LOAD_TIMEOUT_MS
        local entity = 0

        while GetGameTimer() < deadline do
            entity = GetEntityFromStateBagName(bagName)

            if entity and entity ~= 0 then break end

            Wait(50)
        end

        if not entity or entity == 0 then return end

        if not value then
            strip(entity)

            return
        end

        fit(entity, value)
    end)
end)

CreateThread(function()
    while true do
        Wait(2000)

        for entity in pairs(fitted) do
            if not DoesEntityExist(entity) then strip(entity) end
        end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end

    for entity in pairs(fitted) do strip(entity) end
end)

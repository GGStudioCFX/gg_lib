
local RESOURCE = GetCurrentResourceName()

local function channel(name)
    return ("gg_settings:%s:%s"):format(RESOURCE, name)
end

local revision = -1

local function pullSnapshot()
    local ok, payload = GGCallback.await(channel("snapshot"))

    if not ok or type(payload) ~= "table" then return false end

    revision = payload.revision or 0
    settings.resolve(payload.values or {})

    return true
end

local function same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end

    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

-- After a missed change the whole set is read again, and only what differs
-- from what is running is applied, defaults included for cleared ones.
local resyncing = false

local function resync()
    if resyncing then return end
    resyncing = true

    local called, ok, payload = pcall(GGCallback.await, channel("snapshot"))

    resyncing = false

    if not called or not ok or type(payload) ~= "table" then return end
    if (payload.revision or 0) <= revision then return end

    local stored = payload.values or {}
    local moved = {}

    for path, def in pairs(settings.schema) do
        if not settings.isSecret(path) then
            local value = stored[path]
            if value == nil then value = settings.deepCopy(def.default) end

            if not same(value, settings.read(path)) then moved[path] = value end
        end
    end

    revision = payload.revision
    settings.applyLive(moved)
end

AddEventHandler("gg_lib:settings:rowAction", function(resource, id, row, token)
    if resource ~= RESOURCE then return end

    local handler = settings.rowActions and settings.rowActions[id]
    if not handler then return end

    local answered = false

    local function done(ok, valueOrMessage)
        if answered then return end
        answered = true

        TriggerEvent("gg_lib:settings:rowActionResult", token, ok ~= false, valueOrMessage)
    end

    local ran, err = pcall(handler, row, done)

    if not ran then
        gg.print.error(("Settings row action '%s' failed: %s"):format(tostring(id), tostring(err)))
        done(false, tostring(err))
    end
end)

local stopping = {}

AddEventHandler("gg_lib:settings:actionStop", function(token)
    stopping[token] = true
end)

AddEventHandler("gg_lib:settings:action", function(resource, path, token)
    if resource ~= RESOURCE then return end

    local handler = settings.actions and settings.actions[path]
    if not handler then return end

    local answered = false

    local function done(ok, message)
        if answered then return end
        answered = true

        stopping[token] = nil

        TriggerEvent("gg_lib:settings:actionResult", token, ok ~= false, message)
    end

    -- Says where the work is up to, and answers false once the person watching
    -- has asked for it to end. One function both ways: anything long enough to
    -- be worth reporting is long enough to be worth calling off.
    local function report(info)
        if type(info) == "table" then
            TriggerEvent("gg_lib:settings:actionProgress", token, info)
        end

        return not stopping[token]
    end

    local ran, err = pcall(handler, done, report)

    if not ran then
        gg.print.error(("Settings action '%s' failed: %s"):format(tostring(path), tostring(err)))
        done(false, tostring(err))
    end
end)

RegisterNetEvent(channel("sync"), function(payload)
    if type(payload) ~= "table" then return end
    if payload.resource ~= RESOURCE then return end

    if payload.revision and payload.revision <= revision then return end

    -- A large change travels paced and can land after a later one.
    if payload.revision and revision >= 0 and payload.revision > revision + 1 then
        CreateThread(resync)
        return
    end

    revision = payload.revision or revision
    settings.applyLive(payload.values or {})
end)

CreateThread(function()
    for _ = 1, 20 do
        if pullSnapshot() then return end
        Wait(1000)
    end

    gg.print.warn("Could not pull settings from the server; running on defaults")

    settings.resolve({})
end)

RegisterNetEvent("gg_lib:generic:sync", function(payload)
    settings.generic.apply(payload)
end)

-- gg_lib holds one copy for every script on this client; an older gg_lib
-- without it is asked directly, as before.
AddEventHandler("gg_lib:generic:ready", function(payload)
    if type(payload) == "table" then settings.generic.apply(payload) end
end)

local function sharedGeneric()
    local ok, payload = pcall(function()
        return exports.gg_lib:ggGenericSnapshot()
    end)

    if not ok then return nil, true end

    return type(payload) == "table" and payload or nil, false
end

CreateThread(function()
    for _ = 1, 20 do
        local payload, missing = sharedGeneric()

        if payload then
            settings.generic.apply(payload)
            return
        end

        if missing then
            local called, ok, answer = pcall(GGCallback.await, "gg_lib:generic:snapshot")

            if called and ok and type(answer) == "table" then
                settings.generic.apply(answer)
                return
            end
        elseif settings.generic.isResolved() then
            return
        end

        Wait(1000)
    end

    if settings.generic.isResolved() then return end

    gg.print.warn("Could not pull generic settings from gg_lib; cfg.generic is empty")
end)

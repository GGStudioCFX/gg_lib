
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

AddEventHandler("gg_lib:settings:action", function(resource, path, token)
    if resource ~= RESOURCE then return end

    local handler = settings.actions and settings.actions[path]
    if not handler then return end

    local answered = false

    local function done(ok, message)
        if answered then return end
        answered = true

        TriggerEvent("gg_lib:settings:actionResult", token, ok ~= false, message)
    end

    local ran, err = pcall(handler, done)

    if not ran then
        gg.print.error(("Settings action '%s' failed: %s"):format(tostring(path), tostring(err)))
        done(false, tostring(err))
    end
end)

RegisterNetEvent(channel("sync"), function(payload)
    if type(payload) ~= "table" then return end
    if payload.resource ~= RESOURCE then return end

    if payload.revision and payload.revision <= revision then return end

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

CreateThread(function()
    for _ = 1, 20 do
        local called, ok, payload = pcall(GGCallback.await, "gg_lib:generic:snapshot")

        if called and ok and type(payload) == "table" then
            settings.generic.apply(payload)
            return
        end

        Wait(1000)
    end

    gg.print.warn("Could not pull generic settings from gg_lib; cfg.generic is empty")
end)

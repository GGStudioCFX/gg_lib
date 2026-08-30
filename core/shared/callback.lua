-- Adapted from ox_lib (LGPL-3.0-or-later), Copyright (c) Linden.
-- https://github.com/overextended/ox_lib
GGCallback = GGCallback or {}

local RESOURCE = GetCurrentResourceName()
local EVENT    = "__gg_cb_%s"
local SERVER   = IsDuplicityVersion()

local TIMEOUT = GetConvarInt("gg:callbackTimeout", 300000)

local pending = {}

RegisterNetEvent(EVENT:format(RESOURCE), function(key, ...)
    -- A server answer always carries a source; "" means a local resource forged it.
    if not SERVER and source == "" then return end

    local waiting = pending[key]

    if not waiting then return end

    pending[key] = nil

    waiting(...)
end)

local function keyFor(name, target)
    local key

    repeat
        key = ("%s:%s:%s"):format(name, math.random(0, 100000), target or "s")
    until not pending[key]

    return key
end

local function ask(name, target, cb, ...)
    if SERVER and not DoesPlayerExist(target) then
        error(("gg.callback: player %s is not here to answer '%s'"):format(tostring(target), name), 3)
    end

    local key = keyFor(name, target)

    if SERVER then
        TriggerClientEvent(EVENT:format(name), target, RESOURCE, key, ...)
    else
        TriggerServerEvent(EVENT:format(name), RESOURCE, key, ...)
    end

    local waiting = not cb and promise.new()

    pending[key] = function(...)
        if waiting then return waiting:resolve({ ... }) end

        if cb then cb(...) end
    end

    if not waiting then return end

    SetTimeout(TIMEOUT, function()
        if not pending[key] then return end

        pending[key] = nil

        waiting:reject(("gg.callback: '%s' did not answer within %ds -- is it registered on the other side?"):format(name, TIMEOUT // 1000))
    end)

    return table.unpack(Citizen.Await(waiting))
end

function GGCallback.await(name, ...)
    if not SERVER then return ask(name, nil, false, ...) end

    local target = ...

    return ask(name, target, false, select(2, ...))
end

function GGCallback.request(name, ...)
    if not SERVER then
        local cb = ...

        if type(cb) ~= "function" then
            error("gg.callback.request wants a function to hand the answer to -- use gg.callback.await to wait for it instead", 2)
        end

        return ask(name, nil, cb, select(2, ...))
    end

    local target, cb = ...

    if type(cb) ~= "function" then
        error("gg.callback.request wants a function to hand the answer to -- use gg.callback.await to wait for it instead", 2)
    end

    return ask(name, target, cb, select(3, ...))
end

local function answered(ok, ...)
    if ok then return ... end

    local err = ...

    print(("^1[gg_lib] callback error: %s^0"):format(tostring(err)))

    return nil
end

function GGCallback.register(name, cb)
    if type(name) ~= "string" or name == "" then error("gg.callback.register wants a name", 2) end
    if type(cb) ~= "function" then error(("gg.callback.register('%s') wants a function"):format(name), 2) end

    RegisterNetEvent(EVENT:format(name), function(resource, key, ...)
        if SERVER then
            TriggerClientEvent(EVENT:format(resource), source, key, answered(pcall(cb, source, ...)))
        else
            TriggerServerEvent(EVENT:format(resource), key, answered(pcall(cb, ...)))
        end
    end)
end

return GGCallback

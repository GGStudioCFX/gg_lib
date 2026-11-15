
-- One copy of the generic settings per client. Scripts read it from here
-- instead of each asking the server for the same thing when a player joins.
GenericStore = GenericStore or {}

local held = nil   -- { revision, values }
local waiting = {}

local function copy(value)
    if type(value) ~= "table" then return value end

    local out = {}
    for key, inner in pairs(value) do out[key] = copy(inner) end
    return out
end

local function landed(payload)
    held = { revision = payload.revision or 0, values = payload.values or {} }

    local queued = waiting
    waiting = {}

    for index = 1, #queued do pcall(queued[index], held) end

    TriggerEvent("gg_lib:generic:ready", held)
end

local function pull()
    for _ = 1, 20 do
        local called, ok, payload = pcall(GGCallback.await, "gg_lib:generic:snapshot")

        if called and ok and type(payload) == "table" then
            landed(payload)
            return true
        end

        Wait(1000)
    end

    return false
end

function GenericStore.current()
    return held
end

function GenericStore.onReady(fn)
    if held then return fn(held) end

    waiting[#waiting + 1] = fn
end

exports("ggGenericSnapshot", function()
    return held and copy(held) or nil
end)

RegisterNetEvent("gg_lib:generic:sync", function(payload)
    if type(payload) ~= "table" or not held then return end

    local revision = payload.revision

    if revision and revision <= held.revision then return end

    -- A gap means a change was missed; the whole set is read again.
    if revision and revision > held.revision + 1 then
        CreateThread(pull)
        return
    end

    for path, value in pairs(payload.values or {}) do held.values[path] = value end

    held.revision = revision or held.revision
end)

CreateThread(pull)

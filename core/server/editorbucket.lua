
gg = gg or {}
gg.print = gg.print or { error = print, warn = print, log = print }

local EDITOR_BUCKET = 21847

local MAX_SESSION_MS = 20 * 60 * 1000
local SWEEP_MS = 60000

local occupants = {}  -- src -> { bucket = previous, since = ms }

local function restore(src)
    local record = occupants[src]
    if not record then return false end

    occupants[src] = nil

    if GetPlayerName(src) then
        SetPlayerRoutingBucket(src, record.bucket or 0)
    end

    return true
end

local function enter(src)
    if occupants[src] then return true end

    local previous = GetPlayerRoutingBucket(src) or 0

    if previous == EDITOR_BUCKET then previous = 0 end

    occupants[src] = { bucket = previous, since = GetGameTimer() }

    SetPlayerRoutingBucket(src, EDITOR_BUCKET)

    return true
end

GGCallback.register("gg_lib:editor:bucketEnter", function(source)
    return enter(source)
end)

GGCallback.register("gg_lib:editor:bucketLeave", function(source)
    restore(source)

    return true
end)

AddEventHandler("playerDropped", function()
    occupants[source] = nil
end)

CreateThread(function()
    while true do
        Wait(SWEEP_MS)

        local now = GetGameTimer()

        for src, record in pairs(occupants) do
            if not GetPlayerName(src) then
                occupants[src] = nil
            elseif (now - record.since) > MAX_SESSION_MS then
                gg.print.warn(("Editor bucket: pulling %s back after %d minutes"):format(src, MAX_SESSION_MS // 60000))
                restore(src)
            end
        end
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for src in pairs(occupants) do
        restore(src)
    end
end)

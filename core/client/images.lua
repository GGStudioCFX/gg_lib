
-- Pictures from the database image store. Every script's gg.images.fetch
-- comes through here, and so does Script Studio, so one client keeps one set
-- of requests going to the server.

local CHUNK = 60
local RETRY_WAIT = 750
local DEFAULT_TIMEOUT = 30000

local jobs = {}
local nextRequest = 0

-- Batches can land out of order, so a request is done once it holds as many
-- as the server said it would send.
RegisterNetEvent("gg_lib:images:batch", function(request, seq, items, total, reason)
    -- A server answer always carries a source; "" means a local resource forged it.
    if source == "" then return end

    local job = jobs[request]
    if not job then return end

    seq = math.tointeger(seq) or 0

    if seq > 0 then
        TriggerServerEvent("gg_lib:images:ack", request, seq)

        if job.got[seq] then return end

        job.got[seq] = true
        job.count = job.count + 1
    end

    if type(items) == "table" then
        for _, item in ipairs(items) do
            if type(item) == "table" and type(item.n) == "string" and type(item.d) == "string" then
                job.result[item.n] = {
                    data    = ("data:%s;base64,%s"):format(type(item.m) == "string" and item.m or "image/webp", item.d),
                    version = tonumber(item.v),
                }
            end
        end
    end

    if reason or job.count >= (tonumber(total) or 0) then
        jobs[request] = nil
        job.done:resolve(reason or false)
    end
end)

-- One request of at most CHUNK names. Answers with the server's reason, or
-- nil once every picture it had is in `result`.
local function ask(owner, names, result, wait)
    nextRequest = nextRequest + 1

    local request = nextRequest
    local job = { result = result, done = promise.new(), got = {}, count = 0 }

    jobs[request] = job

    TriggerServerEvent("gg_lib:images:fetch", request, owner, names)

    SetTimeout(math.max(0, wait), function()
        if jobs[request] ~= job then return end

        jobs[request] = nil
        TriggerServerEvent("gg_lib:images:cancel", request)
        job.done:resolve("timed out")
    end)

    return Citizen.Await(job.done) or nil
end

-- { [name] = { data = "data:image/webp;base64,...", version = n } } for every
-- name that has a picture, and a reason as a second value when something
-- went wrong (what arrived before it is still returned).
local function fetch(owner, names, timeoutMs)
    local result = {}

    if type(owner) ~= "string" or owner == "" then return result, "invalid owner" end
    if type(names) == "string" then names = { names } end
    if type(names) ~= "table" then return result, "no names" end

    local list, seen = {}, {}

    for _, name in ipairs(names) do
        if math.type(name) == "integer" then name = tostring(name) end

        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end

    local deadline = GetGameTimer() + (tonumber(timeoutMs) or DEFAULT_TIMEOUT)
    local failure = nil

    for first = 1, #list, CHUNK do
        local chunk = table.move(list, first, math.min(#list, first + CHUNK - 1), 1, {})

        while true do
            local left = deadline - GetGameTimer()
            if left <= 0 then return result, "timed out" end

            local reason = ask(owner, chunk, result, left)

            if reason == "busy" or reason == "rate" then
                Wait(math.min(RETRY_WAIT, math.max(0, deadline - GetGameTimer())))
            elseif reason == "timed out" then
                return result, reason
            else
                failure = failure or reason
                break
            end
        end
    end

    return result, failure
end

exports("ggImageFetch", fetch)

-- Script Studio's pictures for "db:<name>" values, owned by the script whose
-- settings are open.
RegisterNUICallback("gg_images_fetch", function(data, cb)
    local owner = type(data) == "table" and data.owner or nil
    local names = type(data) == "table" and data.names or nil

    if type(owner) ~= "string" or type(names) ~= "table" then
        cb({ images = {} })
        return
    end

    local images = fetch(owner, names, 20000)

    cb({ images = images })
end)

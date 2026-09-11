
-- Nothing on the client can read the F8 console, so every VM that runs this
-- keeps its own copy of what it printed or threw. gg_lib's own VM runs it
-- from the manifest; every script that imports gg_lib runs it from init.lua,
-- and the runtime reports script errors through Citizen.Trace, so wrapping
-- that and print catches both.

local RESOURCE = GetCurrentResourceName()
local OWN = RESOURCE == "gg_lib"

local KEEP = 200

local kept, first, last = {}, 1, 0
local inPrint = false

local function keep(text)
    local body = tostring(text):gsub("\n+$", "")
    if body == "" then return end

    last = last + 1
    kept[last] = { t = GetGameTimer(), s = body }

    while last - first + 1 > KEEP do
        kept[first] = nil
        first = first + 1
    end
end

local function snapshot()
    local out = {}

    for index = first, last do
        out[#out + 1] = { r = RESOURCE, t = kept[index].t, s = kept[index].s }
    end

    return out
end

do
    local originalPrint = print
    local originalTrace = Citizen.Trace

    print = function(...)
        local parts = {}

        for index = 1, select("#", ...) do
            parts[index] = tostring((select(index, ...)))
        end

        pcall(keep, table.concat(parts, "\t"))

        inPrint = true
        originalPrint(...)
        inPrint = false
    end

    Citizen.Trace = function(text)
        if not inPrint then pcall(keep, text) end

        return originalTrace(text)
    end
end

if OWN then
    GGConsole = {}

    local waiting = {}

    AddEventHandler("gg_lib:console:lines", function(nonce, resource, rows)
        local bucket = waiting[nonce]
        if not bucket or type(rows) ~= "table" then return end

        for _, row in ipairs(rows) do
            if type(row) == "table" and type(row.s) == "string" then
                bucket[#bucket + 1] = { r = tostring(resource), t = tonumber(row.t) or 0, s = row.s }
            end
        end
    end)

    function GGConsole.collect()
        local nonce = ("%d.%d"):format(GetGameTimer(), math.random(1, 1000000))
        local rows = snapshot()

        waiting[nonce] = rows

        TriggerEvent("gg_lib:console:collect", nonce)
        Wait(150)

        waiting[nonce] = nil

        table.sort(rows, function(a, b) return a.t < b.t end)

        return rows
    end
else
    AddEventHandler("gg_lib:console:collect", function(nonce)
        TriggerEvent("gg_lib:console:lines", nonce, RESOURCE, snapshot())
    end)
end

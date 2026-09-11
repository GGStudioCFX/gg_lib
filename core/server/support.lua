
Support = {}

local MAX_LINES = 1500
local MAX_BYTES = 256 * 1024

local lines, first, last, bytes = {}, 1, 0, 0

local function push(text)
    last = last + 1
    lines[last] = text
    bytes = bytes + #text

    while last > first and (last - first + 1 > MAX_LINES or bytes > MAX_BYTES) do
        bytes = bytes - #lines[first]
        lines[first] = nil
        first = first + 1
    end
end

local function clean(text)
    return (tostring(text or ""):gsub("%^%d", ""):gsub("\r", ""))
end

-- Called from wherever the console prints, so nothing in here may print,
-- call a native, or yield: a print would loop, and the thread is not ours.
local function remember(channel, message)
    local body = clean(message):gsub("\n+$", "")
    if body == "" then return end

    local stamp = os.date("%H:%M:%S")
    local head = true

    for line in (body .. "\n"):gmatch("(.-)\n") do
        if head then
            push(("%s [%s] %s"):format(stamp, channel or "?", line))
            head = false
        else
            push(("         %s"):format(line))
        end
    end
end

-- What was printed before this file ran -- the boot, and anything that
-- started ahead of gg_lib -- is only in the runtime's own buffer.
if type(GetConsoleBuffer) == "function" then
    local ok, buffer = pcall(GetConsoleBuffer)

    if ok and type(buffer) == "string" then
        for line in (clean(buffer):gsub("\n+$", "") .. "\n"):gmatch("(.-)\n") do
            if line ~= "" then push(line) end
        end
    end
end

if type(RegisterConsoleListener) == "function" then
    RegisterConsoleListener(function(channel, message)
        pcall(remember, channel, message)
    end)
end

function Support.consoleText()
    local out = {}

    for index = first, last do
        out[#out + 1] = lines[index]
    end

    return table.concat(out, "\n"), #out
end

local function scripts()
    local out = {}

    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)

        if name and name:sub(1, 3) == "gg_" then
            out[#out + 1] = {
                name    = name,
                version = GetResourceMetadata(name, "version", 0) or "",
                state   = GetResourceState(name),
            }
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)

    return out
end

local function bridges()
    local out = {}

    for _, category in ipairs({ "framework", "inventory", "target", "dispatch", "fuel", "keys", "phone" }) do
        out[#out + 1] = { category = category, resource = Bridges and Bridges.wired and Bridges.wired(category) or "?" }
    end

    return out
end

function Support.info(source)
    if Framework and Framework.ensure then pcall(Framework.ensure) end

    return {
        hostname   = GetConvar("sv_hostname", ""),
        fxserver   = GetConvar("version", ""),
        build      = GetConvar("sv_enforceGameBuild", ""),
        onesync    = GetConvar("onesync", ""),
        txadmin    = GetConvar("txAdmin-version", ""),
        players    = #GetPlayers(),
        resources  = GetNumResources(),
        uptime     = GetGameTimer(),
        clock      = os.date("!%Y-%m-%d %H:%M:%S UTC"),
        version    = GetResourceMetadata("gg_lib", "version", 0) or "",
        mysql      = GetResourceMetadata("oxmysql", "version", 0) or "",
        language   = GenericSettings and GenericSettings.get and GenericSettings.get("general.language") or "en",
        who        = GGName and GGName.both and GGName.both(source) or "",
        identifier = GGName and GGName.identifier and GGName.identifier(source) or "",
        scripts    = scripts(),
        bridges    = bridges(),
    }
end

GGCallback.register("gg_lib:support:bundle", function(source)
    if not Admins.isAdmin(source) then return false end

    local allowed = Admins.can(source, "logs")
    local text, count = nil, 0

    if allowed then text, count = Support.consoleText() end

    return true, {
        info    = Support.info(source),
        console = text,
        lines   = count,
        denied  = not allowed,
    }
end)

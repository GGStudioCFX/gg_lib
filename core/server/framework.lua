Framework = {}

local RESOURCE = GetCurrentResourceName()

local ready = false
local lastTry = 0
local RETRY_MS = 10000

local function runFile(path)
    local source = LoadResourceFile(RESOURCE, path)
    if not source or source == "" then return false end

    local chunk = load(source, ("@@%s/%s"):format(RESOURCE, path), "t")
    if not chunk then return false end

    return (pcall(chunk))
end

-- gg_lib's own VM starts with no gg table at all -- consumers get one from
-- init.lua, but the library's own server code does not. Anything in core that
-- needs the framework or inventory bridge has to ask for them first.
--
-- The latch only closes once a bridge actually answered. A server whose
-- framework starts after gg_lib would otherwise be stuck with whatever was
-- resolved during the first second of boot.
function Framework.ensure()
    if ready then return true end

    local now = GetGameTimer()

    if lastTry > 0 and now - lastTry < RETRY_MS then return false end

    lastTry = now

    gg = gg or {}
    gg.context = "server"
    gg.print   = gg.print or { warn = function() end }
    gg.bridge  = gg.bridge or {}

    gg.bridge.framework = Bridges and Bridges.wired and Bridges.wired("framework") or "default"
    gg.bridge.inventory = Bridges and Bridges.wired and Bridges.wired("inventory") or "default"

    runFile(("bridge/framework/%s/server.lua"):format(gg.bridge.framework))
    runFile(("bridge/inventory/%s/server.lua"):format(gg.bridge.inventory))

    runFile("modules/items/shared.lua")
    runFile("modules/vehicles/shared.lua")

    ready = type(gg.framework) == "table" and type(gg.framework.GetName) == "function"

    return ready
end


if not _VERSION:find("5.4") then
    error("gg_lib requires Lua 5.4. Add `lua54 'yes'` to your fxmanifest.lua")
end

local GG_LIB   = "gg_lib"
local RESOURCE = GetCurrentResourceName()

if gg and gg.__lib == GG_LIB then
    error(("gg_lib loaded twice. Remove the duplicate '@gg_lib/init.lua' from %s/fxmanifest.lua"):format(RESOURCE))
end

local state = GetResourceState(GG_LIB)
if state ~= "started" and state ~= "starting" then
    error(("gg_lib is not started. Ensure it starts before %s in your server.cfg"):format(RESOURCE))
end

local context = IsDuplicityVersion() and "server" or "client"

local function readFile(path)
    return LoadResourceFile(GG_LIB, path)
end

local function loadChunk(path, env)
    local source = readFile(path)
    if not source or source == "" then return nil end

    local chunk, err = load(source, ("@@%s/%s"):format(GG_LIB, path), "t", env)
    if not chunk then
        error(("gg_lib failed to compile %s: %s"):format(path, err))
    end

    return chunk
end

local moduleEnv = setmetatable({}, {
    __index = _ENV,
    __newindex = function(_, key, value)
        _ENV[key] = value
    end,
})

local moduleState = {}

local function runModule(name)
    local current = moduleState[name]
    if current then return current == "loaded" end

    moduleState[name] = "loading"

    local ran = false
    local ok, err = pcall(function()
        for _, file in ipairs({ "shared", context }) do
            local chunk = loadChunk(("modules/%s/%s.lua"):format(name, file), moduleEnv)

            if chunk then
                chunk()
                ran = true
            end
        end
    end)

    if not ok then
        moduleState[name] = nil
        error(err, 0)
    end

    moduleState[name] = ran and "loaded" or "missing"

    return ran
end

gg = setmetatable({
    __lib   = GG_LIB,
    context = context,
}, {
    __index = function(self, name)
        if type(name) ~= "string" then return nil end

        runModule(name)

        return rawget(self, name)
    end,
})

do
    local chunk = loadChunk("core/shared/callback.lua", moduleEnv)

    if chunk then chunk() end
end

rawset(gg, "callback", GGCallback)

local manifest do
    local chunk = loadChunk("bridge/manifest.lua")
    manifest = chunk()
end

local required = manifest.required or {}

local fallback do
    local chunk = loadChunk("bridge/fallback.lua", moduleEnv)
    fallback = (chunk and chunk()) or {}
end

local storedOverrides = {}

do
    local ok, stored = pcall(function() return GlobalState.gg_bridge_overrides end)

    if ok and type(stored) == "table" then storedOverrides = stored end
end

local debugWanted = false

do
    local ok, stored = pcall(function() return GlobalState.gg_debug end)

    if ok then debugWanted = stored == true end
end

local function detectBridge(category)
    local override = storedOverrides[category]

    if override and override ~= "" then
        local overrideState = GetResourceState(override)
        local running = overrideState == "started" or overrideState == "starting"

        if not running then
            print(("^3[gg_lib] the Bridges page picks %s = '%s', but that resource is not started^0"):format(category, override))
        end

        return override, {
            source  = "stored",
            state   = overrideState,
            running = running,
        }
    end

    for _, candidate in ipairs(manifest.categories[category]) do
        local candidateState = GetResourceState(candidate)

        if candidateState == "started" or candidateState == "starting" then
            return candidate, { source = "detected", state = candidateState, running = true }
        end
    end

    return "default", { source = "default", state = "started", running = true }
end

gg.bridge = {}

gg.bridge_status = {}

local function installBridge(category, quiet)
    local resolved, detail = detectBridge(category)
    gg.bridge[category] = resolved

    local loaded = false
    local failure

    if not detail.running then
        failure = ("'%s' is not started"):format(resolved)
    end

    if resolved == "default" then
        local install = fallback[category]

        if install then
            local ok, err = pcall(install)

            loaded = ok

            if not ok then failure = tostring(err) end
        end

        if required[category] and not quiet then
            print(("^1[gg_lib] %s has no %s. Every %s call will do nothing until one of these is started BEFORE it: %s^0"):format(
                RESOURCE, category, category, table.concat(manifest.categories[category] or {}, ", ")))
        end
    else
        local chunk  = loadChunk(("bridge/%s/%s/%s.lua"):format(category, resolved, context), moduleEnv)
        local shared = not chunk and loadChunk(("bridge/%s/%s.lua"):format(category, context), moduleEnv) or nil

        local ok, err = true, nil

        if chunk then
            ok, err = pcall(chunk)
        elseif shared then
            ok, err = pcall(function()
                local install = shared()

                if type(install) ~= "function" then
                    error(("bridge/%s/%s.lua must return a function"):format(category, context))
                end

                if not install(resolved) then
                    error(("bridge/%s/%s.lua has no entry for '%s'"):format(category, context, resolved))
                end
            end)
        end

        loaded = ok

        if not ok then
            failure = tostring(err)

            if not quiet then
                print(("^1[gg_lib] bridge %s/%s failed to load in %s: %s^0"):format(category, resolved, RESOURCE, err))
            end
        end
    end

    gg.bridge_status[category] = {
        category = category,
        resource = resolved,
        source   = detail.source,
        state    = detail.state,
        loaded   = loaded and detail.running,
        error    = failure,
        stub     = resolved == "default",
    }

    if debugWanted then
        print(("[gg_lib] %s: %s -> %s"):format(RESOURCE, category, resolved))
    end

    return gg.bridge_status[category]
end

for _, category in ipairs(manifest.category_order) do
    installBridge(category)
end

local function wants(category, started)
    if storedOverrides[category] == started then return true end
    if storedOverrides[category] and storedOverrides[category] ~= "" then return false end

    for _, candidate in ipairs(manifest.categories[category] or {}) do
        if candidate == started then return true end
    end

    return false
end

-- Detection runs at file scope, so a resource that starts after this script
-- was never seen. Without this the category keeps the do-nothing fallback for
-- the whole session and every call silently returns false.
AddEventHandler(context == "server" and "onResourceStart" or "onClientResourceStart", function(started)
    if type(started) ~= "string" or started == RESOURCE then return end

    for _, category in ipairs(manifest.category_order) do
        local status = gg.bridge_status[category]

        if status and (status.stub or not status.loaded) and wants(category, started) then
            local now = installBridge(category, true)

            if now.loaded then
                print(("[gg_lib] %s: %s is up now, %s bridge loaded"):format(RESOURCE, started, category))
            end
        end
    end
end)

for _, name in ipairs(manifest.modules) do
    local ok, err = pcall(runModule, name)
    if not ok then
        print(("^1[gg_lib] module %s failed to load in %s: %s^0"):format(name, RESOURCE, err))
    end
end

for index = 1, GetNumResourceMetadata(RESOURCE, "gg_lib") do
    local name = GetResourceMetadata(RESOURCE, "gg_lib", index - 1)

    if name and name ~= "" then
        local ok, err = pcall(runModule, name)
        if not ok then
            print(("^1[gg_lib] module %s failed to load in %s: %s^0"):format(name, RESOURCE, err))
        end
    end
end

CreateThread(function()
    Wait(0)
    TriggerEvent(("%s:%s:onResourceStart"):format(RESOURCE, context))
end)

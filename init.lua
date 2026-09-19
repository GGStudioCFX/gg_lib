
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

if context == "client" then
    local chunk = loadChunk("core/client/console.lua", moduleEnv)

    if chunk then pcall(chunk) end
end

local function loadDefaults()
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

            if not running and category ~= "dispatch" then
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

    -- A target script takes registrations -- zones, peds, models -- and keeps
    -- them only as long as it runs. Every call through gg.target is written to
    -- a journal here, compacted so a removal cancels its add, and the journal
    -- is played back into the target script whenever it starts: the first
    -- time, or again after a restart. While it is away the journal answers.
    local REPLAYABLE = { target = true }
    local JOURNAL_LIMIT = 1000

    local ZONE_ADDS = { addBoxZone = true, addSphereZone = true, addPolyZone = true }
    local ALIASES = { AddTargetEntity = "addEntity", removeTargetEntity = "removeEntity", RemoveZone = "removeZone" }

    local journals = {}
    local zoneCount = 0

    local function modelKey(models)
        if type(models) ~= "table" then return tostring(models) end

        local parts = {}

        for index = 1, #models do parts[index] = tostring(models[index]) end

        table.sort(parts)

        return table.concat(parts, ",")
    end

    local function keyOf(name, args)
        if name == "addEntity" then return "entity", args[1], "add" end
        if name == "removeEntity" then return "entity", args[1], args[2] == nil and "clear" or "part" end
        if name == "addModel" then return "model", modelKey(args[1]), "add" end
        if name == "removeModel" then return "model", modelKey(args[1]), args[2] == nil and "clear" or "part" end
        if ZONE_ADDS[name] then return "zone", args[1].name, "add" end
        if name == "removeZone" then return "zone", args[1], "clear" end
        if name == "disable" then return "disable", "", "set" end

        local global = name:match("^addGlobal(%a+)$")
        if global then return "global", global, "add" end

        global = name:match("^removeGlobal(%a+)$")
        if global then return "global", global, args[1] == nil and "clear" or "part" end

        return nil
    end

    local function record(journal, name, args)
        local kind, key, op = keyOf(name, args)
        if not kind then return end

        if op == "clear" or op == "set" then
            for index = #journal, 1, -1 do
                local entry = journal[index]

                if entry.kind == kind and entry.key == key then table.remove(journal, index) end
            end

            if op == "clear" then return end
        end

        journal[#journal + 1] = { kind = kind, key = key, name = name, args = args }

        if #journal > JOURNAL_LIMIT then table.remove(journal, 1) end
    end

    local function answer(name, args)
        if ZONE_ADDS[name] then return args[1].name end
        if name == "isActive" then return false end
        if name == "disable" then return nil end

        return true
    end

    local function proxy(api, state, name)
        local canonical = ALIASES[name]

        if canonical then
            return function(...) return api[canonical](...) end
        end

        if name == "AddBoxZone" then
            return function(zoneName, coords, size, parameters)
                local options = type(parameters) == "table" and (parameters.options or parameters) or {}
                local distance = type(parameters) == "table" and parameters.distance or nil

                return api.addBoxZone({ name = zoneName, coords = coords, size = size, options = options, distance = distance })
            end
        end

        return function(...)
            local args = table.pack(...)

            -- A zone answers with its name, before the target script is up
            -- and after: every target script takes a name where it takes an id.
            if ZONE_ADDS[name] then
                local copy = {}

                if type(args[1]) == "table" then
                    for key, value in pairs(args[1]) do copy[key] = value end
                end

                if copy.name == nil then
                    zoneCount = zoneCount + 1
                    copy.name = ("%s_zone_%d"):format(RESOURCE, zoneCount)
                end

                args = table.pack(copy)
            end

            record(state.journal, name, args)

            local backend = state.backend

            if backend and backend[name] then
                local result = backend[name](table.unpack(args, 1, args.n))

                return ZONE_ADDS[name] and args[1].name or result
            end

            return answer(name, args)
        end
    end

    local function replay(state)
        local journal, backend = state.journal, state.backend
        local played, index = 0, 1

        while index <= #journal do
            local entry = journal[index]

            if entry.kind == "entity" and type(DoesEntityExist) == "function" and not DoesEntityExist(entry.key) then
                table.remove(journal, index)
            else
                local fn = backend[entry.name]

                if type(fn) == "function" and pcall(fn, table.unpack(entry.args, 1, entry.args.n)) then
                    played = played + 1
                end

                index = index + 1
            end
        end

        return played
    end

    -- Wraps whatever installBridge just put in gg[category]. A real bridge
    -- becomes the backend and the journal is played into it; the fallback is
    -- left unused, the proxies answering in its place.
    local function attach(category, live)
        local api = rawget(gg, category)
        if type(api) ~= "table" then return 0 end

        local state = journals[category] or { journal = {} }
        journals[category] = state

        state.backend = nil

        if live then
            state.backend = {}

            for name, fn in pairs(api) do
                if type(fn) == "function" then state.backend[name] = fn end
            end
        end

        for name, fn in pairs(api) do
            if type(fn) == "function" then api[name] = proxy(api, state, name) end
        end

        return live and replay(state) or 0
    end

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

            local clientOnly = context == "server" and (manifest.client_only or {})[category]

            if required[category] and not quiet and not clientOnly then
                if REPLAYABLE[category] then
                    print(("^3[gg_lib] %s has no %s yet. Its %s calls are held and replayed once one of these starts: %s^0"):format(
                        RESOURCE, category, category, table.concat(manifest.categories[category] or {}, ", ")))
                else
                    print(("^1[gg_lib] %s has no %s. Every %s call will do nothing until one of these is started BEFORE it: %s^0"):format(
                        RESOURCE, category, category, table.concat(manifest.categories[category] or {}, ", ")))
                end
            end
        else
            local chunk  = loadChunk(("bridge/%s/%s/%s.lua"):format(category, resolved, context), moduleEnv)
            local shared = not chunk and loadChunk(("bridge/%s/%s.lua"):format(category, context), moduleEnv) or nil

            local ok, err = true, nil

            if category == "dispatch" and not detail.running then
                local install = fallback[category]
                if install then pcall(install) end
                ok = false
            elseif chunk then
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

            if not ok and err then
                failure = tostring(err)

                if category == "dispatch" and fallback.dispatch then pcall(fallback.dispatch) end

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

        if REPLAYABLE[category] and context == "client" then
            gg.bridge_status[category].replayed = attach(category, loaded and detail.running and resolved ~= "default")
        end

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
                    local replayed = now.replayed or 0

                    print(("[gg_lib] %s: %s is up now, %s bridge loaded%s"):format(RESOURCE, started, category,
                        replayed > 0 and (", %d registration(s) replayed into it"):format(replayed) or ""))
                end
            end
        end
    end)

    -- The target script going down takes every zone and ped with it. Calls
    -- made while it is away go into the journal like any other, and the whole
    -- journal is played back when it returns.
    if context == "client" then
        AddEventHandler("onClientResourceStop", function(stopped)
            if type(stopped) ~= "string" or stopped == RESOURCE then return end

            for category, state in pairs(journals) do
                local status = gg.bridge_status[category]

                if status and status.loaded and gg.bridge[category] == stopped then
                    state.backend = nil
                    status.loaded = false

                    print(("^3[gg_lib] %s: %s stopped -- %s calls are held until it is back^0"):format(RESOURCE, stopped, category))
                end
            end
        end)
    end

    for _, name in ipairs(manifest.modules) do
        local ok, err = pcall(runModule, name)
        if not ok then
            print(("^1[gg_lib] module %s failed to load in %s: %s^0"):format(name, RESOURCE, err))
        end
    end
end

if GetResourceMetadata(RESOURCE, "gg_lib_mode", 0) ~= "modules" then
    loadDefaults()
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

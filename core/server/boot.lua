
-- `restart gg_lib` stops every resource that declares gg_lib as a dependency,
-- and FXServer does not start them again -- its own source calls that a TODO.
-- This brings back what went down with the library, target and framework
-- scripts first, so the scripts that need them find them started.

Boot = {}

local RESOURCE = GetCurrentResourceName()

local KVP = "gg_lib:downWith"
local WINDOW = 90
local BOOT_GRACE = 60000

local manifest = (function()
    local raw = LoadResourceFile(RESOURCE, "bridge/manifest.lua")
    local chunk = raw and load(raw, "@bridge/manifest.lua", "t")
    local ok, value = pcall(chunk or function() end)

    return ok and type(value) == "table" and value or {}
end)()

local function dependsOnUs(name)
    for _, key in ipairs({ "dependency", "dependencies" }) do
        for index = 0, GetNumResourceMetadata(name, key) - 1 do
            if GetResourceMetadata(name, key, index) == RESOURCE then return true end
        end
    end

    return false
end

local function providerRank(name)
    for rank, category in ipairs(manifest.category_order or {}) do
        for _, candidate in ipairs((manifest.categories or {})[category] or {}) do
            if candidate == name then return rank end
        end
    end

    return math.huge
end

function Boot.ordered(names)
    table.sort(names, function(a, b)
        local ra, rb = providerRank(a), providerRank(b)

        if ra ~= rb then return ra < rb end

        return a < b
    end)

    return names
end

local function readDown()
    local ok, value = pcall(json.decode, GetResourceKvpString(KVP) or "")

    return ok and type(value) == "table" and value or {}
end

local function writeDown(down)
    if next(down) == nil then
        DeleteResourceKvp(KVP)
        return
    end

    SetResourceKvp(KVP, json.encode(down))
end

function Boot.stoppedDependants()
    local out = {}

    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)

        if name and name ~= RESOURCE and GetResourceState(name) == "stopped" and dependsOnUs(name) then
            out[#out + 1] = name
        end
    end

    return Boot.ordered(out)
end

local function allowed()
    return IsPrincipalAceAllowed(("resource.%s"):format(RESOURCE), "command.ensure") == true
end

function Boot.ensure(names, why)
    if #names == 0 then return false end

    if allowed() then
        print(("[gg_lib] %s: %s"):format(why, table.concat(names, ", ")))

        for _, name in ipairs(names) do
            ExecuteCommand(("ensure %s"):format(name))
        end

        return true
    end

    local commands = {}

    for index, name in ipairs(names) do
        commands[index] = "ensure " .. name
    end

    print(("^3[gg_lib] %s: %s\n  Run these, in this order:  %s\n  Or let gg_lib do it, with this in server.cfg:  add_ace resource.%s command.ensure allow^0"):format(
        why, table.concat(names, ", "), table.concat(commands, "; "), RESOURCE))

    return false
end

AddEventHandler("onResourceStop", function(resource)
    if resource == RESOURCE or not dependsOnUs(resource) then return end

    local down = readDown()

    down[resource] = os.time()

    writeDown(down)
end)

-- One that came back on its own is not ours to start.
AddEventHandler("onResourceStart", function(resource)
    if resource == RESOURCE then return end

    local down = readDown()

    if down[resource] == nil then return end

    down[resource] = nil

    writeDown(down)
end)

CreateThread(function()
    Wait(500)

    if GetConvar("gg_lib_restart_dependants", "true") ~= "true" then return end

    -- This early in the server's life it is the startup script running, and
    -- that starts everything itself, in its own order.
    if GetGameTimer() < BOOT_GRACE then
        writeDown({})
        return
    end

    local down, now = readDown(), os.time()
    local names, ours = {}, {}

    for name, at in pairs(down) do
        if type(at) == "number" and now - at <= WINDOW and GetResourceState(name) == "stopped" and dependsOnUs(name) then
            names[#names + 1] = name
            ours[name] = true
        end
    end

    writeDown({})

    Boot.ensure(Boot.ordered(names), "back up -- starting what went down with it")

    local left = {}

    for _, name in ipairs(Boot.stoppedDependants()) do
        if not ours[name] then left[#left + 1] = name end
    end

    if #left > 0 then
        print(("[gg_lib] stopped, and depending on gg_lib: %s -- gg_ensure starts them"):format(table.concat(left, ", ")))
    end
end)

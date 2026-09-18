gg.hud = gg.hud or {}

local RESOURCE = GetCurrentResourceName()

-- MARK: Holders
-- Every script importing gg_lib runs its own copy of this file, so the list of
-- who is hiding the HUD lives on the player's state bag, local only. One script
-- showing the HUD again cannot undo another that is still hiding it.
local KEY = "gg_hud_hidden"

-- Whether the HUD was showing when the first script hid it. A player who had
-- hidden it themselves keeps it hidden after the last script shows it.
local RESTORE = "gg_hud_restore"

local function holders()
    local value = LocalPlayer.state[KEY]

    return type(value) == "table" and value or {}
end

local function store(set)
    LocalPlayer.state:set(KEY, set, false)
end

-- MARK: HUD resource
local seen = {}

local function call(name)
    local resource, backend = gg.hud.resource, gg.hud.backend

    if not resource or type(backend) ~= "table" or type(backend[name]) ~= "function" then return nil end
    if GetResourceState(resource) ~= "started" then return nil end

    local ok, result = pcall(backend[name])

    if ok then return result end

    local key = ("%s:%s"):format(resource, name)

    if not seen[key] then
        seen[key] = true

        print(("^1[gg_lib] %s threw when asked for %s. That is %s's code, not gg_lib's -- send them this:^0\n%s")
            :format(resource, name, resource, tostring(result)))
    end

    return nil
end

-- MARK: While held
local held, native, drawing, watching = false, false, false, false

local function hideNative()
    if drawing then return end
    drawing = true

    CreateThread(function()
        while held and native do
            HideHudAndRadarThisFrame()
            Wait(0)
        end

        drawing = false
    end)
end

-- Some HUDs show themselves when the pause menu closes, hidden or not. Once it
-- has closed and they have had their turn, they are told again.
local PAUSE_SETTLE_MS = 1000

local function watchPause()
    if watching then return end
    watching = true

    CreateThread(function()
        local paused = false

        while held do
            local now = IsPauseMenuActive() == true

            if paused and not now then
                SetTimeout(PAUSE_SETTLE_MS, function()
                    if held then call("hide") end
                end)
            end

            paused = now
            Wait(250)
        end

        watching = false
    end)
end

-- MARK: API
local function release(resource)
    local set = holders()

    if not set[resource] then return false end

    set[resource] = nil
    store(set)

    if next(set) == nil and LocalPlayer.state[RESTORE] ~= false then call("show") end

    return true
end

--- Hides the HUD resource until this script calls show. `options.native` also
--- hides the game's own HUD and minimap, every frame, for as long as it holds.
function gg.hud.hide(options)
    native = type(options) == "table" and options.native == true
    held = true

    if native then hideNative() end
    watchPause()

    local set = holders()

    if set[RESOURCE] then return true end

    local first = next(set) == nil

    set[RESOURCE] = true
    store(set)

    if first then
        LocalPlayer.state:set(RESTORE, call("visible") ~= false, false)
        call("hide")
    end

    return true
end

--- Takes back this script's hide. The HUD returns once no script is hiding it.
function gg.hud.show()
    held = false
    release(RESOURCE)

    return true
end

--- Whether any script is hiding the HUD right now.
function gg.hud.isHidden()
    return next(holders()) ~= nil
end

-- MARK: Lifecycle
-- A script that stops while hiding would leave the HUD hidden for the rest of
-- the session. Every copy watches for it, its own stop included.
AddEventHandler("onClientResourceStop", function(stopped)
    if type(stopped) ~= "string" then return end

    if stopped == RESOURCE then held = false end

    release(stopped)
end)

-- A HUD shows itself when it starts. Once it has settled, a script still
-- holding it hides it again -- also covering a HUD that starts after we did.
local SETTLE_MS = 3000

AddEventHandler("onClientResourceStart", function(started)
    if type(started) ~= "string" or not holders()[RESOURCE] then return end

    SetTimeout(SETTLE_MS, function()
        if gg.hud.resource == started and holders()[RESOURCE] then call("hide") end
    end)
end)

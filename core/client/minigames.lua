
local RESOURCE = GetCurrentResourceName()

local GAMES = {
    skillcheck = { cursor = false, defaults = { rounds = 3, zone = 40, speed = 220 } },
    keymash    = { cursor = false, defaults = { time = 6, decay = 16, gain = 6 } },
    timing     = { cursor = false, defaults = { rounds = 3, zone = 16, speed = 0.7 } },
    sequence   = { cursor = false, defaults = { length = 6, time = 5 } },
    memory     = { cursor = true,  defaults = { size = 4, flashes = 5, time = 8 } },
    wordwiz    = { cursor = false, defaults = { length = 6, time = 10 } },
    connect    = { cursor = true,  defaults = { pairs = 4, time = 45 } },
    hold       = { cursor = false, defaults = { rounds = 3, zone = 18, speed = 55, time = 8 } },
    reflex     = { cursor = false, defaults = { rounds = 4, window = 1.3 } },
    breach     = { cursor = true,  defaults = { size = 5, length = 4, time = 30 } },
    lockpick   = { cursor = false, defaults = { rounds = 3, zone = 34, speed = 150, time = 25 } },
    codecrack  = { cursor = false, defaults = { length = 4, rounds = 5, time = 45 } },
}

local WATCHDOG_MS = 120000

local active = nil

local function resolveConfig(name, opts)
    local merged = {}

    for key, value in pairs(GAMES[name].defaults) do merged[key] = value end

    if type(opts) == "table" then
        for key, value in pairs(opts) do merged[key] = value end
    end

    if merged.keys == nil and type(merged.key) == "string" then
        local pool = {}

        for character in merged.key:upper():gmatch("[A-Z0-9]") do
            pool[#pool + 1] = character
        end

        if #pool > 0 then merged.keys = pool end
    end

    merged.key = nil

    return merged
end

local function play(name, opts)
    local game = GAMES[name]

    if not game then return false, ("'%s' is not a minigame"):format(tostring(name)) end
    if active then return false, "a minigame is already running" end

    active = promise.new()

    local hadFocus = IsNuiFocused()

    GG_PAUSE_GUARD.acquire()
    SetNuiFocus(true, game.cursor)

    SendNUIMessage({
        action = "minigame_start",
        data   = { NAME = name, CONFIG = resolveConfig(name, opts) },
    })

    local watchdog = active

    SetTimeout(WATCHDOG_MS, function()
        if active ~= watchdog then return end

        SendNUIMessage({ action = "minigame_cancel", data = {} })
        watchdog:resolve(false)
    end)

    local success = Citizen.Await(active)

    active = nil

    SetNuiFocus(hadFocus, hadFocus)
    GG_PAUSE_GUARD.release()

    return success == true
end

local function shout(name)
    local ped = PlayerPedId()
    local id  = GetSoundId()

    PlaySoundFromEntity(id, name, ped, nil, false, 0)

    SetTimeout(6000, function() ReleaseSoundId(id) end)

    TriggerServerEvent("gg_lib:sound:shout", name, nil, 12.0)
end

RegisterNUICallback("minigame_click", function(data, cb)
    cb({ ok = true })

    PlaySoundFrontend(-1, (data and data.good) and "HACKING_CLICK_GOOD" or "HACKING_CLICK_BAD", nil, false)
end)

RegisterNUICallback("minigame_finish", function(data, cb)
    cb("ok")

    if not active then return end

    local won = data and data.success == true

    shout(won and "HACKING_SUCCESS" or "HACKING_FAILURE")

    active:resolve(won)
end)

RegisterNUICallback("minigame_try", function(data, cb)
    cb({ ok = true })

    local name = data and data.name

    if type(name) ~= "string" or not GAMES[name] then return end

    CreateThread(function()
        play(name, {})
    end)
end)

exports("ggMinigame", function(name, opts)
    return play(name, opts)
end)

exports("ggMinigameCancel", function()
    if not active then return false end

    SendNUIMessage({ action = "minigame_cancel", data = {} })

    return true
end)

exports("ggMinigameActive", function()
    return active ~= nil
end)

for name in pairs(GAMES) do
    exports(("gg%s%s"):format(name:sub(1, 1):upper(), name:sub(2)), function(opts)
        return play(name, opts)
    end)
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= RESOURCE then return end

    if active then active:resolve(false) end
end)

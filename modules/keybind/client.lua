gg.keybind = gg.keybind or {}

local SPECIAL = {
    b_100 = "LMB", b_101 = "RMB", b_102 = "MMB",
    b_103 = "Mouse 4", b_104 = "Mouse 5", b_105 = "Mouse 6",
    b_106 = "Mouse 7", b_107 = "Mouse 8", b_108 = "Mouse 9",
    b_115 = "Scroll Down", b_116 = "Scroll Up",

    b_1000 = "L-Shift", b_1002 = "Tab", b_1003 = "Enter", b_1004 = "Backspace",
    b_1012 = "Caps", b_1013 = "L-Ctrl", b_1014 = "R-Ctrl", b_1015 = "L-Alt",
    b_2000 = "Space",

    b_170 = "F1", b_171 = "F2", b_172 = "F3", b_173 = "F4",
    b_174 = "F5", b_175 = "F6", b_176 = "F7", b_177 = "F8",
    b_178 = "F9", b_179 = "F10", b_180 = "F11", b_181 = "F12",

    b_194 = "Up", b_195 = "Down", b_196 = "Left", b_197 = "Right",

    b_130 = "Num -", b_131 = "Num +",
    b_140 = "Num 4", b_141 = "Num 5", b_142 = "Num 6",
    b_143 = "Num 7", b_144 = "Num 8", b_145 = "Num 9",

    b_198 = "Delete", b_199 = "Escape", b_200 = "Insert",
    b_210 = "Delete", b_211 = "Insert", b_212 = "End",
    b_1008 = "Home", b_1009 = "Page Up", b_1010 = "Page Down",
    b_1055 = "Home", b_1056 = "Page Up",
}

local WATCH_MS = 1000

local binds    = {}   -- id -> { hash, label, key }
local watchers = {}
local watching = false

local function readable(token)
    if type(token) ~= "string" or token == "" or token == "NULL" then return "" end

    local plain = token:match("^t_(.+)$")

    if plain then return plain end

    return SPECIAL[token] or token
end

local function readKey(hash)
    local token = GetControlInstructionalButton(2, hash, true)

    if not token or token == "" or token == "NULL" then
        token = GetControlInstructionalButton(0, hash, true)
    end

    return readable(token)
end

local function sweep()
    if watching then return end

    watching = true

    CreateThread(function()
        while next(binds) do
            local changed = false
            local keys    = {}

            for id, bind in pairs(binds) do
                local key = readKey(bind.hash)

                if key ~= bind.key then
                    bind.key = key
                    changed  = true
                end

                keys[id] = key
            end

            if changed then
                for index = 1, #watchers do
                    pcall(watchers[index], keys)
                end
            end

            Wait(WATCH_MS)
        end

        watching = false
    end)
end

function gg.keybind.register(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then return nil end

    if binds[data.id] then return binds[data.id].key end

    local command = ("+%s_%s"):format(GetCurrentResourceName(), data.id)

    RegisterCommand(command, function()
        if IsPauseMenuActive() then return end

        if data.pressed then pcall(data.pressed) end
    end, false)

    RegisterCommand(("-%s_%s"):format(GetCurrentResourceName(), data.id), function()
        if IsPauseMenuActive() then return end

        if data.released then pcall(data.released) end
    end, false)

    RegisterKeyMapping(command, data.label or data.id, data.mapper or "keyboard", data.key or "")

    local hash = joaat(command) | 0x80000000

    binds[data.id] = { hash = hash, label = data.label or data.id, key = "" }

    CreateThread(function()
        Wait(500)

        binds[data.id].key = readKey(hash)

        sweep()
    end)

    SetTimeout(500, function()
        TriggerEvent("chat:removeSuggestion", ("/%s"):format(command))
        TriggerEvent("chat:removeSuggestion", ("/-%s_%s"):format(GetCurrentResourceName(), data.id))
    end)

    return binds[data.id].key
end

function gg.keybind.current(id)
    local bind = binds[id]

    if not bind then return "" end

    bind.key = readKey(bind.hash)

    return bind.key
end

function gg.keybind.all()
    local out = {}

    for id, bind in pairs(binds) do out[id] = readKey(bind.hash) end

    return out
end

function gg.keybind.onChange(fn)
    if type(fn) ~= "function" then return end

    watchers[#watchers + 1] = fn

    sweep()
end

function gg.keybind.label(id)
    local bind = binds[id]

    return bind and bind.label or ""
end

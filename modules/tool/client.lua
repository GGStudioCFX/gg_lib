gg.tool = gg.tool or {}

local BLOCKED = { 24, 25, 37, 38, 44, 47, 50, 68, 69, 70, 91, 92, 114, 121, 140, 141, 142, 143, 191, 199, 200, 257, 263, 264, 331 }

local active = false
local current = nil

local last_info = nil

local function showLegend(options)
    local keys = {}

    for index = 1, #options.keys do
        local key = options.keys[index]

        if key.label and key.key then
            keys[#keys + 1] = { key = key.key, label = key.label }
        end
    end

    SendNUIMessage({
        action = "gg_tool",
        data   = { ACTIVE = true, TITLE = options.title or "Tool", MODE = options.mode, KEYS = keys },
    })
end

function gg.tool.setInfo(rows, mode)
    if not active then return end

    local signature = mode or ""

    for index = 1, #rows do
        signature = ("%s|%s=%s"):format(signature, rows[index].label, rows[index].value)
    end

    if signature == last_info then return end

    last_info = signature

    SendNUIMessage({ action = "gg_tool", data = { ACTIVE = true, MODE = mode, INFO = rows } })
end

local function hideLegend()
    SendNUIMessage({ action = "gg_tool", data = { ACTIVE = false } })
end

function gg.tool.run(options)
    if active then return nil end
    if type(options) ~= "table" or type(options.keys) ~= "table" then return nil end

    active  = true
    current = options

    local state = options.state or {}
    state.tool  = options
    state.done  = false

    local result = nil

    showLegend(options)

    local deadline = GetGameTimer() + 300000

    local ok, err = pcall(function()
        while active and not state.done and GetGameTimer() < deadline do
            for index = 1, #BLOCKED do
                DisableControlAction(0, BLOCKED[index], true)
            end

            if IsPauseMenuActive() then
                SetFrontendActive(false)
            end

            if options.tick then options.tick(state) end

            for index = 1, #options.keys do
                local key = options.keys[index]
                local pressed = key.repeatable and IsDisabledControlPressed(0, key.control)
                    or IsDisabledControlJustPressed(0, key.control)

                if pressed then
                    if key.cancel then
                        state.done = true
                        result = nil
                    elseif key.finish then
                        state.done = true
                        result = key.finish(state)
                    elseif key.action then
                        key.action(state)
                    end

                    break
                end
            end

            Wait(0)
        end
    end)

    active    = false
    current   = nil
    last_info = nil

    hideLegend()

    if options.cleanup then pcall(options.cleanup, state) end

    if not ok then
        gg.print.error(("Tool '%s' failed: %s"):format(options.title or "?", err))
        return nil
    end

    return result
end

function gg.tool.isActive()
    return active
end

function gg.tool.setKeys(keys)
    if not active or not current or type(keys) ~= "table" then return end

    current.keys = keys
    showLegend(current)
end

function gg.tool.abort()
    if not active then return end

    active = false
    hideLegend()
end

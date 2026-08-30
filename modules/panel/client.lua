gg.panel = gg.panel or {}

local shown  = nil   -- the payload as the caller gave it, binds unresolved
local hooked = false
local asleep = false -- something else owns the screen

local function resolve(payload)
    local out = {}

    for key, value in pairs(payload) do out[key] = value end

    if type(payload.hints) == "table" then
        local hints = {}

        for index = 1, #payload.hints do
            local hint = payload.hints[index]

            hints[index] = {
                key   = hint.bind and gg.keybind.current(hint.bind) or hint.key or "",
                label = hint.label or (hint.bind and gg.keybind.label(hint.bind)) or "",
            }
        end

        out.hints = hints
    end

    if payload.toggleBind then
        out.toggleKey = gg.keybind.current(payload.toggleBind)
        out.toggleBind = nil
    end

    return out
end

local function push()
    if asleep or not shown then return false end

    return exports.gg_lib:ggPanelUpdate(resolve(shown)) ~= false
end

local function follow()
    if hooked then return end

    hooked = true

    gg.keybind.onChange(push)
end

function gg.panel.show(data)
    if type(data) ~= "table" then return false end

    if not asleep then
        local nui = rawget(gg, "nui")

        if nui and nui.isBusy and nui.isBusy() then asleep = true end
    end

    shown = shown or {}

    for key, value in pairs(data) do shown[key] = value end

    shown.enabled = true

    follow()

    if asleep then return true end

    return push()
end

function gg.panel.toggle(open)
    if asleep then return false end

    return exports.gg_lib:ggPanelToggle(open) == true
end

function gg.panel.isOpen()
    return exports.gg_lib:ggPanelIsOpen() == true
end

function gg.panel.isShowing()
    return shown ~= nil
end

function gg.panel.hide()
    shown = nil

    exports.gg_lib:ggPanelHide()
end

function gg.panel.suspend()
    if asleep then return end

    asleep = true

    exports.gg_lib:ggPanelHide()
end

function gg.panel.resume()
    if not asleep then return end

    asleep = false

    push()
end

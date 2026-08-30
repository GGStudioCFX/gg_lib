
local function generic(path)
    if settings and settings.generic and settings.generic.get then
        return settings.generic.get(path)
    end

    return nil
end

local function defaultPosition()
    local stored = generic("popup.position")

    return type(stored) == "string" and stored ~= "" and stored or "bottom-middle"
end

local VARIANTS = { info = true, keybind = true, warn = true }

local state = {
    enabled  = false,
    message  = "",
    position = "bottom-middle",
    variant  = "info",
    keybind  = "",
    accent   = "",
}

local function update(partial)
    if type(partial) ~= "table" then return end

    local out = {}

    if partial.position == nil and state.position ~= defaultPosition() then
        state.position = defaultPosition()
        out.position = state.position
    end

    if type(partial.position) == "string" and partial.position ~= state.position then
        state.position = partial.position
        out.position = partial.position
    end

    if type(partial.message) == "string" and partial.message ~= state.message then
        state.message = partial.message
        out.message = partial.message
    end

    if type(partial.variant) == "string" then
        local variant = VARIANTS[partial.variant] and partial.variant or "info"

        if variant ~= state.variant then
            state.variant = variant
            out.variant = variant
        end
    end

    if type(partial.accent) == "string" and partial.accent ~= state.accent then
        state.accent = partial.accent
        out.accent = partial.accent
    end

    if type(partial.keybind) == "string" and partial.keybind ~= state.keybind then
        state.keybind = partial.keybind
        out.keybind = partial.keybind
    end

    local enabled = partial.enabled

    if enabled == nil and type(partial.message) == "string" and partial.message ~= "" and not state.enabled then
        enabled = true
    end

    if type(enabled) == "boolean" and enabled ~= state.enabled then
        state.enabled = enabled
        out.enabled = enabled
    end

    if next(out) == nil then return end

    SendNUIMessage({
        action = "popup_update",
        data   = out,
    })
end

exports("ggPopupUpdate", update)

GGPopup = GGPopup or {}

local flashing = 0

function GGPopup.flash(message, duration)
    if type(message) ~= "string" or message == "" then return end

    local before = {
        enabled = state.enabled,
        message = state.message,
        variant = state.variant,
    }

    flashing = flashing + 1

    local mine = flashing

    update({ enabled = true, message = message, variant = "warn" })

    SetTimeout(type(duration) == "number" and duration or 4000, function()
        if flashing ~= mine then return end

        if before.enabled then
            update(before)
        else
            update({ enabled = false, message = before.message, variant = before.variant })
        end
    end)
end

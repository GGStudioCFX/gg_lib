
gg.popup = gg.popup or {}

function gg.popup.update(partial)
    exports.gg_lib:ggPopupUpdate(partial)
end

function gg.popup.message(msg)
    gg.popup.update({ message = msg })
end

function gg.popup.toggle(bool)
    gg.popup.update({ enabled = bool == true })
end

function gg.popup.show(msg, position)
    gg.popup.update({ message = msg, position = position, enabled = true })
end

local function options(opts)
    if type(opts) == "table" then return opts end

    return { position = opts }
end

function gg.popup.info(msg, opts)
    opts = options(opts)

    gg.popup.update({ message = msg, position = opts.position, accent = opts.accent or "", variant = "info", keybind = "", enabled = true })
end

function gg.popup.keybind(key, msg, opts)
    opts = options(opts)

    gg.popup.update({ message = msg, position = opts.position, accent = opts.accent or "", variant = "keybind", keybind = tostring(key or ""), enabled = true })
end

function gg.popup.warn(msg, opts)
    opts = options(opts)

    gg.popup.update({ message = msg, position = opts.position, accent = "", variant = "warn", keybind = "", enabled = true })
end

function gg.popup.hide()
    gg.popup.update({ enabled = false })
end

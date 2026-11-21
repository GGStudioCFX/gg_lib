gg.menu = gg.menu or {}

local function useLation()
    local choice = settings and settings.generic and settings.generic.get("interface.contextmenu")

    if choice == "ox" then return false end
    if choice == "lation" then return true end

    return GetResourceState("lation_ui") == "started"
end

-- ox_lib through its exports, not the global `lib`: the calling script may not load
-- @ox_lib/init.lua (gg_lib#9, same as the display module). Returns false when ox_lib isn't running.
local function ox(name, ...)
    if GetResourceState("ox_lib") ~= "started" then return false end

    return true, exports.ox_lib[name](nil, ...)
end

local function noMenu()
    print(("^3[gg_lib] %s: no menu to show, start ox_lib or lation_ui^0"):format(GetCurrentResourceName()))
end

gg.menu.open = function(data, options)
    local id, title, menu = data.id, data.title, data.menu
    if useLation() then
        exports.lation_ui:registerMenu({
            id = id,
            title = title,
            menu = menu,
            options = table.unpack({options})
        })

        exports.lation_ui:showMenu(id)
    else
        local ran = ox("registerContext", {
            id = id,
            title = title,
            menu = menu,
            options = table.unpack({options})
        })
        if not ran then return noMenu() end

        ox("showContext", id)
    end
end

gg.menu.inputMenu = function(data)
    if type(data) ~= "table" then
        return false
    end

    local title       = data.title or "Input"
    local inputType   = data.type or "number"
    local label       = data.label or "Value"
    local description = data.description or nil
    local required    = data.required ~= false
    local default     = data.default or nil

    local quantity    = type(data.quantity) == "table" and data.quantity or {}
    local min         = tonumber(quantity.min) or 0
    local max         = tonumber(quantity.max) or 999999
    local result      = false

    if useLation() then
        result = exports.lation_ui:input({
            title = title,
            options = {
                {
                    type = inputType,
                    label = label,
                    placeholder = description,
                    min = min,
                    max = max,
                    required = required,
                    default = default,
                },
            }
        })
    else
        local ran, values = ox("inputDialog", title, {
                {
                    type = inputType,
                    label = label,
                    description = description,
                    min = min,
                    max = max,
                    required = required,
                    default = default,
                },
        })
        if not ran then noMenu() end
        result = values
    end

    return result or false
end

gg.menu.alertDialog = function(data)
    if useLation() then
        return exports.lation_ui:alert(data)
    else
        local ran, answer = ox("alertDialog", data)
        if not ran then return noMenu() end

        return answer
    end
end

gg.menu.getOpenContextMenu = function()
    if useLation() then
        return exports.lation_ui:getOpenMenu()
    else
        local _, id = ox("getOpenContextMenu")

        return id
    end
end

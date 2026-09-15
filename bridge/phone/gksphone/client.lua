gg.phone = gg.phone or {}

local NAME = "gksphone"
local apps = {}

local function call(fn)
    local ok, result = pcall(fn)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))
        return nil
    end

    return result
end

gg.phone.resource = NAME

gg.phone.number = function()
    local number = call(function() return exports[NAME]:PhoneNumber() end)
    if number == nil or number == false or number == "" or number == 0 then return nil end
    return tostring(number)
end

gg.phone.hasPhone = function()
    return gg.phone.number() ~= nil
end

gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end
    return call(function()
        return exports[NAME]:Notification({
            title = notification.title or "",
            message = notification.content or notification.message or "",
            icon = notification.icon or (apps[notification.app] or {}).icon,
            duration = notification.timeout or 5000,
            type = "success",
            buttonactive = false,
        }) ~= false
    end) == true
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call")
    return false
end

gg.phone.app = {}

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.phone.app.installed = function(key)
    return apps[key] ~= nil and gg.phone.app.ready()
end

gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    if type(spec.ui) ~= "string" or not spec.ui:match("^https://cfx%-nui%-") then
        return false, "an app needs a resource NUI URL"
    end

    local ok, result = pcall(function()
        return exports[NAME]:AddCustomApp({
            name = spec.key,
            appurl = spec.ui .. (spec.ui:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME,
            icons = spec.icon,
            description = spec.description,
            show = true,
            startapp = spec.defaultApp ~= false,
            labelLangs = spec.labelLangs or { en = spec.name or spec.key },
            onOpen = function()
                gg.phone.app.send(spec.key, "gg_phone_open", {})
            end,
            onClose = function()
                gg.phone.app.send(spec.key, "gg_phone_close", {})
                gg.phone.app.focus(false)
            end,
        })
    end)

    if not ok then return false, tostring(result) end
    if result == false then return false, "app registration refused" end
    apps[spec.key] = spec
    return true
end

gg.phone.app.remove = function(key)
    if not apps[key] then return true end
    -- The documented API has no app-removal export; resource stop owns cleanup.
    return false, "restart the phone and resource with the app disabled to remove it"
end

gg.phone.app.send = function(key, action, data)
    if not apps[key] or not gg.phone.app.ready() then return false end
    return call(function()
        return exports[NAME]:NuiSendMessage({ action = action, data = data }) ~= false
    end) == true
end

gg.phone.app.focus = function(focused)
    if not gg.phone.app.ready() then return false end
    return call(function() return exports[NAME]:InputChange(focused == true) ~= false end) == true
end

gg.phone.app.drain = function() return {} end

AddEventHandler("onClientResourceStop", function(resource)
    if resource == NAME then apps = {} end
    if resource == GetCurrentResourceName() then gg.phone.app.focus(false) end
end)

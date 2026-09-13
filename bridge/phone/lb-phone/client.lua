
gg.phone = gg.phone or {}

-- sd-phone loads this file with its own resource name here. Its compatibility
-- layer answers the lb-phone export, so EXPORT stays lb-phone for it and only
-- NAME -- what GetResourceState is asked about -- changes.
local EXPORT = GG_PHONE_EXPORT or "lb-phone"
local NAME   = GG_PHONE_RESOURCE or EXPORT

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    local sent = attempt(function()
        return exports[EXPORT]:SendNotification({
            app         = notification.app,
            title       = notification.title or "",
            content     = notification.content or notification.message or "",
            timeout     = notification.timeout,
            onClick     = notification.onClick,
            keepOnClick = notification.keepOnClick,
        })
    end)

    return sent ~= nil and sent ~= false
end

gg.phone.number = function()
    return attempt(function()
        return exports[EXPORT]:GetEquippedPhoneNumber()
    end)
end

gg.phone.hasPhone = function()
    local number = gg.phone.number()

    return type(number) == "string" and number ~= ""
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call -- a client cannot address mail to anybody")

    return false
end

RegisterNetEvent("gg_lib:phone:notify", function(notification)
    gg.phone.notify(notification)
end)

gg.phone.resource = NAME

--------------------------------------------------
-- MARK: Custom apps
--------------------------------------------------

gg.phone.app = {}

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

-- lb-phone has no query for this; a defaultApp is installed the moment it is added.
gg.phone.app.installed = function(key)
    return type(key) == "string" and key ~= ""
end

-- lb-phone wants `ui` as "<resource>/<path>" and builds the origin itself, so
-- the scheme a phone-agnostic caller passes is taken off here.
gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end

    local ui = spec.ui

    if type(ui) == "string" then
        ui = ui:gsub("^https?://cfx%-nui%-", "")
    end

    local result = attempt(function()
        return { exports[EXPORT]:AddCustomApp({
            identifier  = spec.key,
            name        = spec.name or spec.key,
            description = spec.description,
            developer   = spec.developer,
            defaultApp  = spec.defaultApp ~= false,
            size        = spec.size,
            ui          = ui,
            icon        = spec.icon,
            fixBlur     = spec.fixBlur ~= false,
        }) }
    end)

    if result == nil then return false, ("%s refused AddCustomApp"):format(NAME) end
    if not result[1] then return false, tostring(result[2]) end

    return true
end

gg.phone.app.remove = function(key)
    if GetResourceState(NAME) ~= "started" then return false end

    return attempt(function()
        exports[EXPORT]:RemoveCustomApp(key)

        return true
    end) == true
end

gg.phone.app.send = function(key, action, data)
    return attempt(function()
        exports[EXPORT]:SendCustomAppMessage(key, { action = action, data = data })

        return true
    end) == true
end


gg.phone = gg.phone or {}

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("lb-phone call failed: %s"):format(tostring(result)))

        return nil
    end

    return result
end

gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    local sent = attempt(function()
        return exports["lb-phone"]:SendNotification({
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
        return exports["lb-phone"]:GetEquippedPhoneNumber()
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

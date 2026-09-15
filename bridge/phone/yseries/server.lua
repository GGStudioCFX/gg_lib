
gg.phone = gg.phone or {}

local NAME = GG_PHONE_EXPORT or "yseries"

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.resource = NAME

gg.phone.number = function(source)
    local n = attempt(function() return exports[NAME]:GetPhoneNumberBySourceId(source) end)

    if n == nil or n == false or n == 0 or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    local receiverType, receiver

    if type(target) == "string" then
        receiverType, receiver = "phoneNumber", target
    else
        receiverType, receiver = "source", target
    end

    if not receiver or receiver == "" then return false end

    local sent = attempt(function()
        return exports[NAME]:SendMail({
            title             = mail.subject or "",
            sender            = mail.sender or "no-reply",
            senderDisplayName = mail.senderName or mail.sender or "no-reply",
            content           = mail.message or mail.body or "",
            actions           = mail.actions,
            attachments       = mail.attachments,
        }, receiverType, receiver)
    end)

    return sent ~= nil and sent ~= false
end

-- The documented return is "true when the phone is disabled", which is not a
-- success flag, so only a throw counts as failure here.
gg.phone.notify = function(source, notification)
    if type(notification) ~= "table" then return false end

    local sent = attempt(function()
        return exports[NAME]:SendNotification({
            app     = notification.app,
            title   = notification.title or "",
            text    = notification.content or notification.message or "",
            timeout = notification.timeout,
            icon    = notification.icon,
        }, "source", source)
    end)

    return sent ~= nil
end

-- The client bridge has no notification export to call, so it sends its own
-- notifications up here. It can only ever address itself.
RegisterNetEvent(GetCurrentResourceName() .. ":server:phone:notify", function(notification)
    local src = source

    if type(notification) ~= "table" then return end

    gg.phone.notify(src, notification)
end)

gg.callback.register("gg_lib:phone:number", function(source)
    return gg.phone.number(source)
end)


gg.phone = gg.phone or {}

local NAME = "codem-phone"

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
    if type(source) ~= "number" or source <= 0 then return nil end

    local n = attempt(function() return exports[NAME]:GetPhoneNumberBySource(source) end)

    if n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

-- A player source goes to that player's active phone. A number is turned into the
-- phone's mail address, which also reaches a phone whose owner is offline.
gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    local sender = mail.sender or "no-reply"

    local body = {
        sender      = mail.senderName or sender,
        senderEmail = type(sender) == "string" and sender:find("@", 1, true) and sender or nil,
        senderIcon  = mail.icon,
        title       = mail.subject or "",
        description = mail.message or mail.body or "",
        attachments = mail.attachments,
        canReply    = mail.canReply == true,
    }

    local sent

    if type(target) == "number" then
        if target <= 0 then return false end

        sent = attempt(function() return exports[NAME]:SendMailBySource(target, body) end)
    else
        if type(target) ~= "string" or target == "" then return false end

        local address = target:find("@", 1, true) and target
            or attempt(function() return exports[NAME]:GetSocialMediaUsername(target, "mail") end)

        if type(address) ~= "string" or address == "" then return false end

        body.to = address

        sent = attempt(function() return exports[NAME]:SendMail(body) end)
    end

    return sent ~= nil and sent ~= false
end

-- The phone styles a notification by the app it belongs to and refuses one
-- without an app, so an unnamed one is shown as a message.
gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or source <= 0 or type(notification) ~= "table" then return false end

    return attempt(function()
        return exports[NAME]:SendNotify(source, {
            app     = notification.app or "message",
            title   = notification.title or "",
            message = notification.content or notification.message or "",
        })
    end) == true
end

-- The client has no notification export, so it sends its own up here; it can only
-- ever address itself. This file can load twice in one resource (a chosen phone
-- that starts later), so the relay and the number callback are added once.
if not GG_PHONE_SERVER_RELAY then
    GG_PHONE_SERVER_RELAY = true

    RegisterNetEvent(GetCurrentResourceName() .. ":server:phone:notify", function(notification)
        local src = source

        if type(notification) ~= "table" then return end

        gg.phone.notify(src, notification)
    end)
end

if not GG_PHONE_NUMBER_CALLBACK then
    GG_PHONE_NUMBER_CALLBACK = true

    gg.callback.register("gg_lib:phone:number", function(source)
        return gg.phone.number(source)
    end)
end

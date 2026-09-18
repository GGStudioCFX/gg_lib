
gg.phone = gg.phone or {}

local NAME = "jpr-phonesystem"

gg.phone.resource = NAME

-- The number lives behind a client export only, so it is asked for over there.
gg.phone.number = function(source)
    local ok, n = pcall(gg.callback.await, "gg_lib:phone:number", source)

    if not ok or n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

-- Online mail is the phone's own server event, addressed to a player source. The
-- phone has no server-side lookup from a number to a player, so a number is refused.
gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    if type(target) ~= "number" or target <= 0 then
        gg.print.warn(("%s mail needs a player source; it cannot address a phone number"):format(NAME))

        return false
    end

    if GetResourceState(NAME) ~= "started" then return false end

    TriggerEvent("jpr-phonesystem:server:sendEmail", {
        subject = mail.subject or "",
        message = mail.message or mail.body or "",
        sender  = mail.sender or "no-reply",
    }, target)

    return true
end

gg.phone.notify = function(source, notification)
    if type(notification) ~= "table" then return false end

    TriggerClientEvent("jpr-phonesystem:client:customnotification", source, {
        app   = "Custom",
        title = notification.title or "",
        img   = notification.icon or "",
        text  = notification.content or notification.message or "",
        time  = notification.timeout or 3000,
    })

    return true
end

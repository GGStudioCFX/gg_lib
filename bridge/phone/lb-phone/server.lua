
gg.phone = gg.phone or {}

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("lb-phone call failed: %s"):format(tostring(result)))

        return nil
    end

    return result
end

gg.phone.number = function(source)
    return attempt(function()
        return exports["lb-phone"]:GetEquippedPhoneNumber(source)
    end)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local number = gg.phone.number(source)

    return type(number) == "string" and number ~= ""
end

gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    local number = type(target) == "string" and target or gg.phone.number(target)

    if not number or number == "" then return false end

    local sent = attempt(function()
        return exports["lb-phone"]:SendMail({
            to      = number,
            sender  = mail.sender or "no-reply",
            subject = mail.subject or "",
            message = mail.message or mail.body or "",
            actions = mail.actions,
            attachments = mail.attachments,
        })
    end)

    return sent ~= nil and sent ~= false
end

gg.phone.notify = function(source, notification)
    if type(notification) ~= "table" then return false end

    TriggerClientEvent("gg_lib:phone:notify", source, notification)

    return true
end

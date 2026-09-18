
gg.phone = gg.phone or {}

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

gg.phone.resource = NAME

gg.phone.number = function(source)
    return attempt(function()
        return exports[EXPORT]:GetEquippedPhoneNumber(source)
    end)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local number = gg.phone.number(source)

    return type(number) == "string" and number ~= ""
end

-- Mail is addressed to the phone's email account, looked up from the number
-- unless an address is given outright.
gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    local address = type(target) == "string" and target:find("@", 1, true) and target or nil

    if not address then
        local number = type(target) == "string" and target or gg.phone.number(target)

        if not number or number == "" then return false end

        address = attempt(function() return exports[EXPORT]:GetEmailAddress(number) end)
    end

    if type(address) ~= "string" or address == "" then return false end

    local sent = attempt(function()
        return exports[EXPORT]:SendMail({
            to      = address,
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

    TriggerClientEvent(GetCurrentResourceName() .. ":client:phone:notify", source, notification)

    return true
end

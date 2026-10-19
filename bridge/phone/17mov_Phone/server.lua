
gg.phone = gg.phone or {}

local NAME = "17mov_Phone"

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

    local n = attempt(function() return exports[NAME]:GetNumberFromPlayer(source) end)

    if n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

-- Image attachments as the phone takes them: a list of URLs.
local function images(attachments)
    if type(attachments) ~= "table" then return nil end

    local list = {}

    for _, attachment in ipairs(attachments) do
        local url = type(attachment) == "string" and attachment
            or type(attachment) == "table" and (attachment.photo or attachment.image or attachment.url)

        if type(url) == "string" and url ~= "" then list[#list + 1] = url end
    end

    return #list > 0 and list or nil
end

-- A player source or a phone number; the phone has no export that takes a mail
-- address. A named sender is shown as given (customUser: no such account needs
-- to exist), otherwise the phone sends it as a system mail.
gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    local topic   = mail.subject or ""
    local message = mail.message or mail.body or ""
    local pics    = images(mail.attachments)
    local sender  = mail.senderName or mail.sender

    local bySource = type(target) == "number"

    if bySource then
        if target <= 0 then return false end
    elseif type(target) ~= "string" or target == "" or target:find("@", 1, true) then
        return false
    end

    local sent = attempt(function()
        if type(sender) == "string" and sender ~= "" then
            if bySource then
                exports[NAME]:Email_SendEmailBySrc(target, sender, topic, message, pics, true)
            else
                exports[NAME]:Email_SendEmailByNumber(target, sender, topic, message, pics, true)
            end
        elseif bySource then
            exports[NAME]:Email_SendSystemEmailBySrc(target, topic, message, pics)
        else
            exports[NAME]:Email_SendSystemEmailByNumber(target, topic, message, pics)
        end

        return true
    end)

    return sent == true
end

gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or source <= 0 or type(notification) ~= "table" then return false end

    return attempt(function()
        exports[NAME]:SendNotificationToSrc(source, {
            app     = notification.app or "SYSTEM",
            title   = notification.title or "",
            message = notification.content or notification.message or "",
        })

        return true
    end) == true
end

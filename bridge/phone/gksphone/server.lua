gg.phone = gg.phone or {}

local NAME = "gksphone"

local function call(fn)
    local ok, result = pcall(fn)
    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))
        return nil
    end
    return result
end

gg.phone.resource = NAME

gg.phone.number = function(source)
    local number = call(function() return exports[NAME]:GetPhoneBySource(source) end)
    if number == nil or number == false or number == "" or number == 0 then return nil end
    return tostring(number)
end

gg.phone.numberOf = gg.phone.number
gg.phone.hasPhone = function(source) return gg.phone.number(source) ~= nil end

gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or source <= 0 or type(notification) ~= "table" then return false end
    return call(function()
        return exports[NAME]:sendNotification(source, {
            title = notification.title or "",
            message = notification.content or notification.message or "",
            icon = notification.icon,
            duration = notification.timeout or 5000,
            type = "success",
            buttonactive = false,
        }) ~= false
    end) == true
end

gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end
    local source = target
    if type(target) == "string" then
        source = call(function() return exports[NAME]:GetSourceByPhone(target) end)
    end
    source = tonumber(source)
    if not source or source <= 0 then return false end
    return call(function()
        return exports[NAME]:SendNewMail(source, {
            sender = mail.sender or "no-reply",
            subject = mail.subject or "",
            message = mail.message or mail.body or "",
            image = mail.image,
            attachments = mail.attachments,
        }) ~= false
    end) == true
end

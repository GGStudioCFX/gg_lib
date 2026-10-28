
gg.phone = gg.phone or {}

local NAME = "apex_phone"

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.resource = NAME

-- The phone keeps its accounts under the framework's character id (the citizenid,
-- or ESX's identifier) and looks a number up from that.
local function citizen(source)
    if type(source) ~= "number" or source <= 0 or not (gg.framework and gg.framework.GetIdentifier) then return nil end

    local id = gg.framework.GetIdentifier(source)

    if id == nil or id == false or id == "" then return nil end

    return tostring(id)
end

gg.phone.number = function(source)
    local cid = citizen(source)

    if not cid then return nil end

    local n = attempt(function() return exports[NAME]:GetNumber(cid) end)

    if n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

-- Photo attachments as the phone takes them. One it refuses refuses the whole
-- mail, so only plain http(s) links up to its 512 characters go, at most its 4.
local function photos(attachments)
    if type(attachments) ~= "table" then return nil end

    local list = {}

    for _, attachment in ipairs(attachments) do
        local url = type(attachment) == "string" and attachment
            or type(attachment) == "table" and (attachment.photo or attachment.image or attachment.url)

        if type(url) == "string" and #url <= 512 and url:find("^https?://") and not url:find("[%s\"']") then
            list[#list + 1] = { type = "photo", url = url }

            if #list == 4 then break end
        end
    end

    return #list > 0 and list or nil
end

-- A player source, a phone number or a citizen id. The phone has no lookup by
-- mail address, so an address target answers false.
gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end

    if type(target) == "number" then
        target = citizen(target)
    elseif type(target) ~= "string" or target == "" or target:find("@", 1, true) then
        target = nil
    end

    if not target then return false end

    local address = mail.senderMail or mail.email

    return attempt(function()
        return exports[NAME]:SendMail(target, {
            sender      = mail.senderName or mail.sender or "no-reply",
            email       = type(address) == "string" and address:find("@", 1, true) and address or nil,
            subject     = mail.subject or "",
            body        = mail.message or mail.body or "",
            attachments = photos(mail.attachments),
        })
    end) == true
end

gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or source <= 0 or type(notification) ~= "table" then return false end

    return attempt(function()
        return exports[NAME]:SendNotification(source, {
            app      = notification.app,
            title    = notification.title or "",
            msg      = notification.content or notification.message or "",
            icon     = notification.icon,
            duration = notification.timeout,
        })
    end) == true
end

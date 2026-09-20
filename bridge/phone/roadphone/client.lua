gg.phone = gg.phone or {}

local NAME = "roadphone"
local RESOURCE = GetCurrentResourceName()

local function attempt(fn)
    local ok, result = pcall(fn)
    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))
        return false, nil
    end
    return true, result
end

gg.phone.resource = NAME

gg.phone.number = function()
    local ok, number = attempt(function() return exports[NAME]:getPhoneNumber() end)
    if not ok or number == nil or number == false or number == "" then return nil end
    return tostring(number)
end

gg.phone.hasPhone = function()
    return gg.phone.number() ~= nil
end

gg.phone.notify = function(notification)
    if type(notification) ~= "table" or GetResourceState(NAME) ~= "started" then return false end
    local ok = attempt(function()
        return exports[NAME]:sendNotification({
            apptitle = notification.appTitle or notification.title or notification.app or "GG Studio",
            title = notification.title or "",
            message = notification.content or notification.message or "",
            img = notification.icon,
        })
    end)
    return ok
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call -- a client cannot address mail to anybody")
    return false
end

local mailEvent = RESOURCE .. ":client:phone:mail"
RegisterNetEvent(mailEvent, function(mail)
    if type(mail) ~= "table" or GetResourceState(NAME) ~= "started" then return end
    local sender = mail.senderMail or mail.sender
    if type(sender) ~= "string" or not sender:find("@", 1, true) then sender = "no-reply@ggstudio.store" end
    attempt(function()
        exports[NAME]:sendMail({
            senderMail = sender,
            subject = mail.subject or "",
            message = mail.message or mail.body or "",
            button = mail.button,
        })
    end)
end)

gg.phone.app = {}
local apps, queues = {}, {}
local QUEUE_LIMIT = 50

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.phone.app.installed = function(key)
    return apps[key] == true
end

gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    apps[spec.key] = true
    return true
end

gg.phone.app.remove = function(key)
    apps[key], queues[key] = nil, nil
    return true
end

gg.phone.app.send = function(key, action, data)
    if not apps[key] or type(action) ~= "string" then return false end
    local queue = queues[key] or {}
    queues[key] = queue
    queue[#queue + 1] = { action = action, data = data }
    if #queue > QUEUE_LIMIT then table.remove(queue, 1) end
    return true
end

gg.phone.app.drain = function(key)
    local queue = queues[key]
    queues[key] = nil
    return queue or {}
end

local typing = false
gg.phone.app.focus = function(focused)
    typing = focused == true
    local ok = attempt(function() exports[NAME]:inputFocus(typing) end)
    return ok
end

AddEventHandler("onResourceStop", function(resource)
    if resource == RESOURCE and typing then gg.phone.app.focus(false) end
end)

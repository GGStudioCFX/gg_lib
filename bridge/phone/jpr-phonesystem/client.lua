
gg.phone = gg.phone or {}

local NAME = "jpr-phonesystem"

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.resource = NAME

gg.phone.number = function()
    local n = attempt(function() return exports[NAME]:getPhoneNumber() end)

    if n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.hasPhone = function()
    local n = gg.phone.number()

    return type(n) == "string" and n ~= ""
end

-- The phone's own server config raises notifications with exactly this event
-- and payload; app must stay "Custom".
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    TriggerEvent("jpr-phonesystem:client:customnotification", {
        app   = "Custom",
        title = notification.title or "",
        img   = notification.icon or "",
        text  = notification.content or notification.message or "",
        time  = notification.timeout or 3000,
    })

    return true
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call -- a client cannot address mail to anybody")

    return false
end

-- The only number export is client-side, so the server asks here.
gg.callback.register("gg_lib:phone:number", function()
    return gg.phone.number()
end)

--------------------------------------------------
-- MARK: Custom apps
--------------------------------------------------

-- JPR has no export that adds an app. Its apps are entries in the phone's own
-- config and a pane in its own index.html, both in escrow_ignore, so the app is
-- installed by hand from the kit the script ships. add() has nothing to do at
-- runtime and says so by answering true.
--
-- The pane is an iframe of the script's own page inside the phone's NUI page.
-- Lua cannot post into another resource's NUI, so send() queues and the page
-- drains the queue through its own resource.
gg.phone.app = {}

local queues = {}

-- The page only drains while its pane is on screen, and a server with the
-- phone but not the kit never drains at all, so the oldest give way.
local QUEUE_LIMIT = 50

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.phone.app.installed = function(key)
    return type(key) == "string" and key ~= ""
end

gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end

    return true
end

gg.phone.app.remove = function(key)
    queues[key] = nil

    return true
end

gg.phone.app.send = function(key, action, data)
    if type(key) ~= "string" or key == "" then return false end

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

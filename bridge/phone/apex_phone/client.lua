
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

-- `app` gives the notification that app's icon; the phone files one with no app
-- under its Settings app. The text goes in `msg`.
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    return attempt(function()
        exports[NAME]:SendNotification({
            app      = notification.app,
            title    = notification.title or "",
            msg      = notification.content or notification.message or "",
            icon     = notification.icon,
            duration = notification.timeout,
        })

        return true
    end) == true
end

gg.phone.number = function()
    local number = attempt(function()
        return exports[NAME]:GetPhoneNumber()
    end)

    if number == nil or number == false or number == "" then return nil end

    return tostring(number)
end

gg.phone.hasPhone = function()
    local number = gg.phone.number()

    return type(number) == "string" and number ~= ""
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call -- a client cannot address mail to anybody")

    return false
end

--------------------------------------------------
-- MARK: Custom apps
--------------------------------------------------

gg.phone.app = {}

local apps, queues = {}, {}
local QUEUE_LIMIT = 50

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.phone.app.installed = function(key)
    return apps[key] ~= nil and gg.phone.app.ready()
end

local function register(app)
    local ok, result = pcall(function()
        return exports[NAME]:RegisterApp(app)
    end)

    if not ok then return false, tostring(result) end
    if result == false then return false, "RegisterApp refused the app (see the apex_phone console line)" end

    return true
end

-- The client RegisterApp takes { id, name, url, icon, category, description }:
-- the page is framed from its own URL and learns which phone holds it from the
-- query string. Every registered app goes on the home screen, so `defaultApp` has
-- nothing to choose here. The phone takes the app off by itself when the script
-- that added it stops.
gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    if type(spec.ui) ~= "string" or spec.ui == "" then
        return false, "an app needs a page"
    end

    local app = {
        id          = spec.key,
        name        = spec.name or spec.key,
        url         = spec.ui .. (spec.ui:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME,
        icon        = spec.icon,
        category    = spec.category,
        description = spec.description,
        job         = spec.job,
    }

    -- Kept even when refused: it is offered again when the phone restarts.
    apps[spec.key] = app

    return register(app)
end

gg.phone.app.remove = function(key)
    if not apps[key] then return true end

    apps[key], queues[key] = nil, nil

    if GetResourceState(NAME) ~= "started" then return false end

    return attempt(function()
        return exports[NAME]:UnregisterApp(key)
    end) == true
end

-- The phone has no way to post into an app's frame, so messages wait here for
-- the page to drain them through its own resource.
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

-- The phone forgets every app when it restarts, so each one is offered again
-- once it is back.
AddEventHandler("onClientResourceStart", function(resource)
    if resource ~= NAME then return end

    SetTimeout(1000, function()
        for key, app in pairs(apps) do
            local added, why = register(app)

            if not added then gg.print.warn(("%s refused %s again: %s"):format(NAME, key, why)) end
        end
    end)
end)

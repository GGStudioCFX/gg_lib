
gg.phone = gg.phone or {}

local NAME = "17mov_Phone"
local RESOURCE = GetCurrentResourceName()

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.resource = NAME

-- `app` names the app the notification belongs to; the phone's own docs use
-- "SYSTEM" for one that belongs to none.
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    return attempt(function()
        exports[NAME]:CreateNotification({
            app     = notification.app or "SYSTEM",
            title   = notification.title or "",
            message = notification.content or notification.message or "",
        })

        return true
    end) == true
end

gg.phone.number = function()
    local number = attempt(function()
        return exports[NAME]:GetPlayerNumber()
    end)

    if number == nil or number == false or number == "" then return nil end

    return tostring(number)
end

gg.phone.hasPhone = function()
    local ok, has = pcall(function()
        return exports[NAME]:HasPhoneItem()
    end)

    if ok and type(has) == "boolean" then return has end

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

local apps, warned = {}, {}

gg.phone.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.phone.app.installed = function(key)
    return apps[key] ~= nil and gg.phone.app.ready()
end

local function register(app)
    local ok, why = pcall(function()
        exports[NAME]:AddApplication(app)
    end)

    if not ok then return false, tostring(why) end

    return true
end

-- The page is framed from its own URL and learns which phone holds it from the
-- query string. defaultApp puts the app on every phone, old ones included, where
-- the player cannot uninstall it; without it the app waits in the phone's store
-- for players to install. The store description
-- and a translated label come from the phone's locale files (Appname:Title,
-- Store:Appname:Description), not from here.
gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    if type(spec.ui) ~= "string" or spec.ui == "" then
        return false, "an app needs a page"
    end

    local installed = spec.defaultApp ~= false

    local app = {
        name           = spec.key,
        label          = spec.name or spec.key,
        ui             = spec.ui .. (spec.ui:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME,
        icon           = spec.icon,
        iconBackground = spec.iconBackground or "#151519",
        default        = installed,
        preInstalled   = installed,
        resourceName   = RESOURCE,
        rating         = spec.rating or 5,
        job            = spec.job,
    }

    -- Kept even when refused: the phone may not have loaded yet, and it is
    -- offered again once it says it is ready.
    apps[spec.key] = app

    return register(app)
end

-- Without `uninstall` the phone only drops the app for now; a default or
-- preinstalled one comes back with the player's choices as they were.
--
-- 17mov's own app template removes its app on stop only in dev mode: in
-- production a server restart can lose the app's data. A script that removes
-- its app while it stops (onClientResourceStop) therefore leaves it on the
-- phone: the removal waits for the next tick, which a stopping resource never
-- gets, and the app registers again when the script starts. A removal at any
-- other time (an owner turning the app off) happens on that tick.
gg.phone.app.remove = function(key)
    if not apps[key] then return true end

    apps[key] = nil

    if GetResourceState(NAME) ~= "started" then return false end

    CreateThread(function()
        if apps[key] or GetResourceState(NAME) ~= "started" then return end

        attempt(function()
            exports[NAME]:RemoveApplication({ name = key, resourceName = RESOURCE })
        end)
    end)

    return true
end

-- The phone posts { action, payload } into the app's frame. A page that is not
-- open can refuse it, so a failure is reported once per app, not per update.
gg.phone.app.send = function(key, action, data)
    if type(action) ~= "string" then return false end

    local ok, why = pcall(function()
        exports[NAME]:SendAppMessage(key, { action = action, payload = data })
    end)

    if not ok and not warned[key] then
        warned[key] = true
        gg.print.warn(("%s SendAppMessage to %s failed: %s"):format(NAME, tostring(key), tostring(why)))
    end

    return ok
end

gg.phone.app.drain = function()
    return {}
end

-- The page holds the phone's setKeepInput itself while a field has the keyboard.
gg.phone.app.focus = function()
    return true
end

-- The phone's own boilerplate registers again whenever the phone says it is
-- ready, so every app added here is offered again then.
RegisterNetEvent("17mov_Phone:Client:Ready", function()
    for key, app in pairs(apps) do
        local added, why = register(app)

        if not added then gg.print.warn(("%s refused %s again: %s"):format(NAME, key, why)) end
    end
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource == NAME then warned = {} end
end)

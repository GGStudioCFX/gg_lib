
gg.phone = gg.phone or {}

-- yphone and yflip-phone load this file with their own name here. Every export
-- is the same across the three; only the resource name differs.
local NAME = GG_PHONE_EXPORT or "yseries"

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

gg.phone.resource = NAME

-- Notifications are a server export on yseries, so the client hands them up.
-- Every importing resource registers this relay, so the event is named after
-- this one: a shared name would show the notification once per resource.
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    TriggerServerEvent(GetCurrentResourceName() .. ":server:phone:notify", notification)

    return true
end

-- There is no client-side number export. Ask the server once and keep the
-- answer; a phone restart may hand the player a different one.
local number = nil
local asked = false

gg.phone.number = function()
    if number then return number end
    if asked then return nil end

    asked = true

    local ok, answer = pcall(gg.callback.await, "gg_lib:phone:number")

    if ok and type(answer) == "string" and answer ~= "" then number = answer end

    return number
end

gg.phone.hasPhone = function()
    local n = gg.phone.number()

    return type(n) == "string" and n ~= ""
end

gg.phone.mail = function()
    gg.print.warn("gg.phone.mail is a server call -- a client cannot address mail to anybody")

    return false
end

AddEventHandler("onClientResourceStart", function(started)
    if started ~= NAME then return end

    number, asked = nil, false
end)

--------------------------------------------------
-- MARK: Custom apps
--------------------------------------------------

gg.phone.app = {}

gg.phone.app.ready = function()
    if GetResourceState(NAME) ~= "started" then return false end

    return attempt(function() return exports[NAME]:GetDataLoaded() end) == true
end

gg.phone.app.installed = function(key)
    return attempt(function() return exports[NAME]:IsAppInstalled(key) end) == true
end

-- The phone iframes `ui` as a plain URL, so the page is told which phone is
-- wrapping it in the query string. lb-phone never sees this; it injects its
-- own globals instead.
gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end

    local ui = spec.ui

    if type(ui) == "string" and ui ~= "" then
        ui = ui .. (ui:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME
    end

    local icon = spec.icon

    local ok, result = pcall(function()
        return exports[NAME]:AddCustomApp({
            key        = spec.key,
            name       = spec.name or spec.key,
            defaultApp = spec.defaultApp ~= false,
            ui         = ui,
            icon       = type(icon) == "table" and icon or { yos = icon, humanoid = icon },
        })
    end)

    if not ok then return false, tostring(result) end
    if result == false then return false, ("%s refused AddCustomApp"):format(NAME) end

    return true
end

gg.phone.app.remove = function(key)
    if GetResourceState(NAME) ~= "started" then return false end

    return attempt(function()
        exports[NAME]:RemoveCustomApp(key)

        return true
    end) == true
end

gg.phone.app.send = function(key, action, data)
    return attempt(function()
        exports[NAME]:SendAppMessage(key, { action = action, data = data })

        return true
    end) == true
end

gg.phone.app.drain = function()
    return {}
end

-- The phone keeps game keys live while an app is open; the app says when a field
-- wants the keyboard, or typing into it reaches the game as well.
local typing = false

gg.phone.app.focus = function(focused)
    typing = focused == true

    return attempt(function()
        exports[NAME]:SetNuiFocusKeepInput(not typing)

        return true
    end) == true
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() and typing then gg.phone.app.focus(false) end
end)


gg.phone = gg.phone or {}

-- Quasar has two phones that take custom apps, and they speak different APIs:
--   Smartphone V3 (qs-smartphone): addCustomApp({ id, label, icon, iframe = { url } }),
--     and getCustomApps lists what is registered.
--   Smartphone PRO (qs-smartphone-pro): addCustomApp({ app, label, ui, image }).
-- qs-smartphone-pro loads this file with its own name here. PRO is also found
-- installed in a folder still called qs-smartphone, and the classic qs-smartphone
-- (the one with qs-base) has no custom apps at all, so under that name the API is
-- told apart by what the resource answers rather than by its name.
local NAME = GG_PHONE_EXPORT or "qs-smartphone"
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

-- "v3" or "pro", nil until the phone answers. Only V3 lists its custom apps;
-- PRO and the classic phone both answer InPhone, and add() tells those two apart.
local api = nil

local function flavour()
    if api then return api end
    if GetResourceState(NAME) ~= "started" then return nil end

    if NAME ~= "qs-smartphone-pro" and pcall(function() return exports[NAME]:getCustomApps() end) then
        api = "v3"
    elseif pcall(function() return exports[NAME]:InPhone() end) then
        api = "pro"
    end

    return api
end

-- PRO shows a notification from the client. V3 documents its notifications on
-- the server only, so the client hands them up to the relay named after this
-- resource, and it can only ever address itself.
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    if flavour() == "pro" then
        return attempt(function()
            exports[NAME]:SendTempNotification({
                title   = notification.title or "",
                text    = notification.content or notification.message or "",
                app     = notification.app,
                timeout = notification.timeout or 5000,
            })

            return true
        end) == true
    end

    TriggerServerEvent(RESOURCE .. ":server:phone:notify", notification)

    return true
end

-- Neither phone has a client-side number export. A found number is kept until the
-- phone restarts or changes device; a missing one is asked for again after a
-- while, not on every call.
local number = nil
local askedAt = nil

gg.phone.number = function()
    if number then return number end
    if askedAt and GetGameTimer() - askedAt < 10000 then return nil end

    askedAt = GetGameTimer()

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

-- The server sends PRO notifications back down here. Named after this resource:
-- every importing resource registers the relay. This file can load twice in one
-- resource (a chosen phone that starts later), so it is added once.
if not GG_PHONE_CLIENT_RELAY then
    GG_PHONE_CLIENT_RELAY = true

    RegisterNetEvent(RESOURCE .. ":client:phone:notify", function(notification)
        gg.phone.notify(notification)
    end)
end

--------------------------------------------------
-- MARK: Custom apps
--------------------------------------------------

gg.phone.app = {}

local apps, queues = {}, {}
local QUEUE_LIMIT = 50

gg.phone.app.ready = function()
    return flavour() ~= nil
end

gg.phone.app.installed = function(key)
    if not apps[key] or not gg.phone.app.ready() then return false end
    if api ~= "v3" then return true end

    local list = attempt(function() return exports[NAME]:getCustomApps() end)

    if type(list) ~= "table" then return false end
    if list[key] ~= nil then return true end

    for _, app in pairs(list) do
        if type(app) == "table" and app.id == key then return true end
    end

    return false
end

-- Both phones iframe the ui URL as given, so the page learns which phone holds
-- it from the query string.
local function framed(url)
    return url .. (url:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME
end

local function register(spec)
    local using = flavour()

    if not using then return false, ("%s has not started"):format(NAME) end

    local ok, added, why = pcall(function()
        if using == "v3" then
            return exports[NAME]:addCustomApp({
                id           = spec.key,
                label        = spec.name or spec.key,
                icon         = spec.icon,
                iframe       = { url = framed(spec.ui) },
                description  = spec.description,
                creator      = spec.developer,
                appStoreOnly = spec.defaultApp == false,
                sizeMb       = type(spec.size) == "number" and math.floor(spec.size / 102.4 + 0.5) / 10 or nil,
            })
        end

        -- PRO's own template fills every field, so the store page has them all.
        -- It reads the icon as image; one known adapter sends icon, so both go.
        return exports[NAME]:addCustomApp({
            app              = spec.key,
            label            = spec.name or spec.key,
            ui               = framed(spec.ui),
            image            = spec.icon,
            icon             = spec.icon,
            description      = spec.description or "",
            creator          = spec.developer or "",
            category         = "social",
            age              = "3+",
            isGame           = false,
            job              = false,
            blockedJobs      = {},
            timeout          = 5000,
            extraDescription = {},
        })
    end)

    if not ok then
        if tostring(added):find("No such export", 1, true) then
            return false, ("%s exports no addCustomApp: the classic Quasar phone takes no custom apps, Smartphone V3 and PRO do"):format(NAME)
        end

        return false, tostring(added)
    end

    if added == false then return false, tostring(why or "app registration refused") end

    return true
end

gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    if type(spec.ui) ~= "string" or spec.ui == "" then
        return false, "an app needs a page"
    end

    local added, why = register(spec)

    if added then apps[spec.key] = spec end

    return added, why
end

-- V3 also drops an app by itself when the resource that added it stops.
gg.phone.app.remove = function(key)
    apps[key], queues[key] = nil, nil

    if GetResourceState(NAME) ~= "started" then return true end

    return attempt(function()
        return exports[NAME]:removeCustomApp(key) ~= false
    end) == true
end

-- Neither phone has a way to post to an app's frame from Lua (Quasar's own V3
-- example app polls for its updates), so they wait here until the page collects
-- them through its own NUI callback.
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

AddEventHandler("onClientResourceStart", function(resource)
    if resource == NAME then api, number, askedAt = nil, nil, nil end
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource == NAME then api, apps, queues = nil, {}, {} end
end)

-- V3 raises this when the player switches device or SIM card.
AddEventHandler("phone:device:phoneChanged", function()
    number, askedAt = nil, nil
end)

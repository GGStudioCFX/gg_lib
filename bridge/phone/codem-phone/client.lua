
gg.phone = gg.phone or {}

local NAME = "codem-phone"
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

-- Notifications are a server export here, so the client hands them up to the
-- relay named after this resource.
gg.phone.notify = function(notification)
    if type(notification) ~= "table" then return false end

    TriggerServerEvent(RESOURCE .. ":server:phone:notify", notification)

    return true
end

-- There is no client-side number export. A found number is kept until the phone
-- reloads; a missing one is asked for again after a while, not on every call.
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
    local ok, added, why = pcall(function()
        return exports[NAME]:AddCustomApp(app)
    end)

    if not ok then return false, tostring(added) end
    if added == false then return false, tostring(why or "app registration refused") end

    return true
end

-- The page is iframed from its own URL and learns which phone holds it from the
-- query string. defaultApp keeps the app on the home grid; without it the app
-- goes to the phone's store for players to install.
gg.phone.app.add = function(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
        return false, "an app needs a key"
    end
    if type(spec.ui) ~= "string" or spec.ui == "" then
        return false, "an app needs a page"
    end

    local installed = spec.defaultApp ~= false

    local app = {
        identifier   = spec.key,
        name         = spec.name or spec.key,
        description  = spec.description,
        developer    = spec.developer,
        ui           = spec.ui .. (spec.ui:find("?", 1, true) and "&" or "?") .. "phone=" .. NAME,
        icon         = spec.icon,
        defaultApp   = installed,
        addAppStore  = not installed,
        notification = true,
        fixBlur      = spec.fixBlur ~= false,
    }

    -- Kept even when refused: the phone may not have loaded yet, and it is
    -- offered again once it has.
    apps[spec.key] = app

    return register(app)
end

-- The documented API has no removal export; the app stays until the phone restarts.
gg.phone.app.remove = function(key)
    if not apps[key] then return true end

    return false, "restart the phone with the app disabled to remove it"
end

-- The phone has no documented way to post to an app's frame, so updates wait
-- here until the page collects them through its own NUI callback.
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

-- The phone cannot see focus inside a frame from another resource, so the page
-- reports it; otherwise typing into a field reaches the game as well.
local typing = false

gg.phone.app.focus = function(focused)
    typing = focused == true

    if not gg.phone.app.ready() then return false end

    return attempt(function()
        exports[NAME]:SetInputFocus(typing)

        return true
    end) == true
end

-- The phone's own example registers again each time a player's phone loads, so
-- every app added here is offered again once it has settled.
RegisterNetEvent("codem-phone:phoneLoaded", function()
    number, askedAt = nil, nil

    SetTimeout(2000, function()
        if not gg.phone.app.ready() then return end

        for key, app in pairs(apps) do
            local added, why = register(app)

            if not added then gg.print.warn(("%s refused %s again: %s"):format(NAME, key, why)) end
        end
    end)
end)

AddEventHandler("onClientResourceStart", function(resource)
    if resource == NAME then number, askedAt = nil, nil end
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource == NAME then apps, queues = {}, {} end
    if resource == RESOURCE and typing then gg.phone.app.focus(false) end
end)

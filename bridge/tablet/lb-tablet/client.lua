gg.tablet = gg.tablet or {}

-- LB Tablet's custom apps, from its client exports (docs.lbscripts.com/tablet/script-integration):
-- AddCustomApp(app) -> success, reason; RemoveCustomApp(identifier) -> success, reason;
-- SendCustomAppMessage(identifier, event, data) -> success, reason. Unlike lb-phone the message
-- takes the event name on its own, and the page subscribes to it with the injected onNuiEvent
-- (useNuiEvent in LB's own templates).
local NAME     = "lb-tablet"
local RESOURCE = GetCurrentResourceName()

-- Only the bridge installed last answers the restart below; an earlier copy goes quiet.
local token = {}
GG_TABLET_LIVE = token

local function call(export, ...)
    local packed = table.pack(pcall(function(...)
        local api = exports[NAME]

        return api[export](api, ...)
    end, ...))

    if not packed[1] then
        gg.print.warn(("%s %s failed: %s"):format(NAME, export, tostring(packed[2])))

        return false
    end

    return true, packed[2], packed[3]
end

-- The page learns its frame from ?tablet=, as the phones that frame a url say ?phone=.
local function withQuery(url, key, value)
    if type(url) ~= "string" or url == "" then return url end

    local base, hash = url:match("^([^#]*)(.*)$")

    return ("%s%s%s=%s%s"):format(base, base:find("?", 1, true) and "&" or "?", key, value, hash)
end

local specs = {}

gg.tablet.resource = NAME
gg.tablet.shared   = nil

gg.tablet.app = {}

gg.tablet.app.ready = function()
    return GetResourceState(NAME) == "started"
end

gg.tablet.app.installed = function(key)
    return specs[key] ~= nil
end

-- The ui and icon go over as full https://cfx-nui-<resource>/ urls: LB's templates hand it a full
-- http url for both while developing, and a bare "ui/index.html" otherwise.
gg.tablet.app.add = function(spec)
    if type(spec) ~= "table" then return false, "an app needs a table" end

    local key = spec.identifier or spec.key

    if type(key) ~= "string" or key == "" then return false, "an app needs an identifier" end

    local app = {
        identifier  = key,
        resource    = RESOURCE,
        name        = spec.name or key,
        description = spec.description,
        developer   = spec.developer,
        defaultApp  = spec.defaultApp ~= false,
        removable   = spec.removable,
        size        = spec.size,
        price       = spec.price,
        images      = spec.images,
        ui          = withQuery(spec.ui, "tablet", NAME),
        icon        = spec.icon,
        onInstall   = spec.onInstall,
        onUninstall = spec.onUninstall,
        onOpen      = spec.onOpen,
        onClose     = spec.onClose,
    }

    local called, ok, reason = call("AddCustomApp", app)

    if not called then return false, ("%s refused AddCustomApp"):format(NAME) end

    -- Still there from before this resource restarted, or added twice: put the new one in its place.
    if not ok and reason == "APP_ALREADY_EXISTS" then
        local removedCall, removed, why = call("RemoveCustomApp", key)

        if not removedCall or removed == false then return false, tostring(why or reason) end

        called, ok, reason = call("AddCustomApp", app)

        if not called then return false, ("%s refused AddCustomApp"):format(NAME) end
    end

    if not ok then return false, tostring(reason) end

    specs[key] = spec

    return true
end

gg.tablet.app.remove = function(key)
    specs[key] = nil

    if GetResourceState(NAME) ~= "started" then return false end

    local called, ok = call("RemoveCustomApp", key)

    return called and ok ~= false
end

gg.tablet.app.send = function(key, action, data)
    local called, ok = call("SendCustomAppMessage", key, action, data)

    return called and ok ~= false
end

-- Pushes straight in; nothing ever waits here.
gg.tablet.app.drain = function()
    return {}
end

-- A restarted tablet has forgotten every app, so each one added here goes back, as LB's own
-- templates do on onResourceStart.
AddEventHandler("onClientResourceStart", function(started)
    if started ~= NAME or GG_TABLET_LIVE ~= token or next(specs) == nil then return end

    SetTimeout(1000, function()
        if GG_TABLET_LIVE ~= token then return end

        for _, spec in pairs(specs) do gg.tablet.app.add(spec) end
    end)
end)

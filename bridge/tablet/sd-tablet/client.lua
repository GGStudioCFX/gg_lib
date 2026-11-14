gg.tablet = gg.tablet or {}

-- sd-tablet has no app list of its own. It runs sd-phone's interface on a tablet-sized screen and
-- shows sd-phone's custom apps, each filtered by its `devices` list ('phone', 'tablet'; none means
-- every device). So an app goes to sd-phone, through sd-phone's own exports (addCustomApp,
-- removeCustomApp, sendCustomAppMessage) rather than its lb-phone layer, which a leftover lb-phone
-- folder or `sd_phone_lbcompat false` turns off. A message is pushed to sd-phone's page, and
-- sd-tablet mirrors every push into its own frame while it is open.
--
-- One registration serves both screens, and registering the same identifier again replaces it.
-- `gg.tablet.shared` names that phone, so a script that also wants the app on the phone puts
-- 'phone' in `devices` here instead of calling gg.phone.app.add as well, which would replace the
-- list with "every device".
local NAME  = "sd-tablet"
local PHONE = "sd-phone"

local DEVICES = { phone = true, tablet = true }

-- Only the bridge installed last answers the restart below; an earlier copy goes quiet.
local token = {}
GG_TABLET_LIVE = token

local function call(export, ...)
    local packed = table.pack(pcall(function(...)
        local api = exports[PHONE]

        return api[export](api, ...)
    end, ...))

    if not packed[1] then
        gg.print.warn(("%s %s failed: %s"):format(PHONE, export, tostring(packed[2])))

        return false
    end

    return true, packed[2], packed[3]
end

local function withQuery(url, key, value)
    if type(url) ~= "string" or url == "" then return url end

    local base, hash = url:match("^([^#]*)(.*)$")

    return ("%s%s%s=%s%s"):format(base, base:find("?", 1, true) and "&" or "?", key, value, hash)
end

--- The screens an app shows on: 'tablet' unless the spec names others.
local function devicesOf(spec)
    local list = spec.devices

    if type(list) == "string" then list = { list } end

    local out, seen = {}, {}

    for _, device in ipairs(type(list) == "table" and list or {}) do
        device = type(device) == "string" and device:lower() or nil

        if device and DEVICES[device] and not seen[device] then
            seen[device] = true
            out[#out + 1] = device
        end
    end

    if #out == 0 then out[1] = "tablet" end

    return out
end

local specs = {}

gg.tablet.resource = NAME
gg.tablet.shared   = PHONE

gg.tablet.app = {}

-- The app list lives in sd-phone, so that is the one that has to be up.
gg.tablet.app.ready = function()
    return GetResourceState(PHONE) == "started"
end

gg.tablet.app.installed = function(key)
    return specs[key] ~= nil
end

gg.tablet.app.add = function(spec)
    if type(spec) ~= "table" then return false, "an app needs a table" end

    local key = spec.identifier or spec.key

    if type(key) ~= "string" or key == "" then return false, "an app needs an identifier" end

    local devices = devicesOf(spec)

    -- The same url serves every screen the app is on, so ?tablet= is only added when the
    -- tablet is the only one. A page on both tells them apart by the frame around it.
    local ui = spec.ui

    if #devices == 1 and devices[1] == "tablet" then ui = withQuery(ui, "tablet", NAME) end

    local called, ok, reason = call("addCustomApp", {
        identifier  = key,
        name        = spec.name or key,
        description = spec.description,
        developer   = spec.developer,
        defaultApp  = spec.defaultApp ~= false,
        size        = spec.size,
        price       = spec.price,
        images      = spec.images,
        ui          = ui,
        icon        = spec.icon,
        fixBlur     = spec.fixBlur ~= false,
        devices     = devices,
        job         = spec.job,
        requires    = spec.requires,
        onOpen      = spec.onOpen,
        onClose     = spec.onClose,
    })

    if not called then return false, ("%s refused addCustomApp"):format(PHONE) end
    if not ok then return false, tostring(reason) end

    specs[key] = spec

    return true
end

gg.tablet.app.remove = function(key)
    specs[key] = nil

    if GetResourceState(PHONE) ~= "started" then return false end

    local called, ok = call("removeCustomApp", key)

    return called and ok ~= false
end

gg.tablet.app.send = function(key, action, data)
    local called, ok = call("sendCustomAppMessage", key, { action = action, data = data })

    return called and ok ~= false
end

gg.tablet.app.drain = function()
    return {}
end

-- sd-phone keeps its app list in its client, so a restart forgets every app; each goes back.
AddEventHandler("onClientResourceStart", function(started)
    if started ~= PHONE or GG_TABLET_LIVE ~= token or next(specs) == nil then return end

    SetTimeout(1000, function()
        if GG_TABLET_LIVE ~= token then return end

        for _, spec in pairs(specs) do gg.tablet.app.add(spec) end
    end)
end)


gg.phone = gg.phone or {}

-- qs-smartphone-pro loads this file with its own name here (see client.lua).
local NAME = GG_PHONE_EXPORT or "qs-smartphone"

gg.phone.resource = NAME

-- "v3" or "pro". Under the qs-smartphone name it is not known until a V3-only
-- export answers, or turns out not to exist: that is PRO in an old folder.
local api = NAME == "qs-smartphone-pro" and "pro" or nil

local function attempt(fn, ...)
    local ok, result = pcall(fn, ...)

    if not ok then
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))

        return nil
    end

    return result
end

-- Runs a V3 export. False when this is not V3, and a missing export settles that.
local function v3(fn)
    if api == "pro" then return false end

    local ok, result = pcall(fn)

    if ok then
        api = "v3"

        return true, result
    end

    if tostring(result):find("No such export", 1, true) then
        api = "pro"
    else
        gg.print.warn(("%s call failed: %s"):format(NAME, tostring(result)))
    end

    return false
end

local function text(value)
    if value == nil or value == false or value == "" or value == 0 then return nil end

    return tostring(value)
end

-- PRO looks a number up by the owner's identifier. Quasar's own example passes
-- the player's first identifier; the phone keys phones by the framework's
-- character identifier, so that is tried first.
local function proNumber(source)
    local tried = {}

    for _, identifier in ipairs({ gg.framework.GetIdentifier and gg.framework.GetIdentifier(source), GetPlayerIdentifier(source, 0) }) do
        if identifier and not tried[identifier] then
            tried[identifier] = true

            local n = text(attempt(function() return exports[NAME]:GetPhoneNumberFromIdentifier(identifier, false) end))

            if n then return n end
        end
    end

    return nil
end

gg.phone.number = function(source)
    if type(source) ~= "number" or source <= 0 then return nil end

    local done, n = v3(function() return exports[NAME]:GetCurrentPhoneNumber(source) end)

    if done then return text(n) end
    if api == "pro" then return proNumber(source) end

    return nil
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

-- V3 mails a player source (subject and body only). A number is matched to the
-- online player holding it; V3 has no lookup from a number, and none from an
-- address. PRO documents no mail export at all.
local warnedMail = false

local function noMail()
    if not warnedMail then
        warnedMail = true

        gg.print.warn(("%s documents no mail export, so gg.phone.mail answers false"):format(NAME))
    end

    return false
end

gg.phone.mail = function(target, mail)
    if type(mail) ~= "table" then return false end
    if api == "pro" then return noMail() end

    local source = target

    if type(target) == "string" then
        if target == "" or target:find("@", 1, true) then return false end

        source = nil

        for _, player in ipairs(GetPlayers()) do
            local id = tonumber(player)

            if id and gg.phone.number(id) == target then
                source = id

                break
            end
        end
    end

    if type(source) ~= "number" or source <= 0 then return false end

    local done, sent = v3(function()
        return exports[NAME]:SendMail(source, mail.subject or "", mail.message or mail.body or "")
    end)

    if done then return sent ~= false end
    if api == "pro" then return noMail() end

    return false
end

-- V3 notifies a player source from here. PRO notifies from the client, so the
-- notification goes down to the relay named after this resource.
gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or source <= 0 or type(notification) ~= "table" then return false end

    local done, sent = v3(function()
        return exports[NAME]:sendPhoneNotification(source, {
            appId = notification.app,
            title = notification.title or "",
            text  = notification.content or notification.message or "",
        })
    end)

    if done then return sent ~= false end
    if api ~= "pro" then return false end

    TriggerClientEvent(GetCurrentResourceName() .. ":client:phone:notify", source, notification)

    return true
end

AddEventHandler("onResourceStart", function(resource)
    if resource == NAME then api = NAME == "qs-smartphone-pro" and "pro" or nil end
end)

-- The client has no notification export on V3, so it sends its own up here; it
-- can only ever address itself. Neither phone has a client-side number export,
-- so the client asks here. This file can load twice in one resource (a chosen
-- phone that starts later), so the relay and the callback are added once.
if not GG_PHONE_SERVER_RELAY then
    GG_PHONE_SERVER_RELAY = true

    RegisterNetEvent(GetCurrentResourceName() .. ":server:phone:notify", function(notification)
        local src = source

        if type(notification) ~= "table" then return end

        gg.phone.notify(src, notification)
    end)
end

if not GG_PHONE_NUMBER_CALLBACK then
    GG_PHONE_NUMBER_CALLBACK = true

    gg.callback.register("gg_lib:phone:number", function(source)
        return gg.phone.number(source)
    end)
end

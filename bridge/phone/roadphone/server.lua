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

gg.phone.number = function(source)
    if type(source) ~= "number" or source <= 0 then return nil end
    local ok, number = attempt(function() return exports[NAME]:GetPhoneNumberBySource(source) end)
    if not ok or number == nil or number == false or number == "" then return nil end
    return tostring(number)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    return gg.phone.number(source) ~= nil
end

gg.phone.notify = function(source, notification)
    if type(source) ~= "number" or type(notification) ~= "table" or GetResourceState(NAME) ~= "started" then return false end
    local ok = attempt(function()
        exports[NAME]:PhoneNotifyPlayer(source, {
            apptitle = notification.appTitle or notification.title or notification.app or "GG Studio",
            title = notification.title or "",
            message = notification.content or notification.message or "",
            img = notification.icon,
        })
    end)
    return ok
end

gg.phone.mail = function(target, mail)
    if type(target) ~= "number" or target <= 0 or type(mail) ~= "table" then return false end
    if GetResourceState(NAME) ~= "started" then return false end
    TriggerClientEvent(RESOURCE .. ":client:phone:mail", target, mail)
    return true
end

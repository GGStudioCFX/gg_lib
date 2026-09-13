
gg.phone = gg.phone or {}

local NAME = "jpr-phonesystem"

gg.phone.resource = NAME

-- The number lives behind a client export only, so it is asked for over there.
gg.phone.number = function(source)
    local ok, n = pcall(gg.callback.await, "gg_lib:phone:number", source)

    if not ok or n == nil or n == false or n == "" then return nil end

    return tostring(n)
end

gg.phone.numberOf = gg.phone.number

gg.phone.hasPhone = function(source)
    local n = gg.phone.number(source)

    return type(n) == "string" and n ~= ""
end

gg.phone.mail = function()
    gg.print.warn(("%s has no mail export; gg.phone.mail does nothing on it"):format(NAME))

    return false
end

gg.phone.notify = function(source, notification)
    if type(notification) ~= "table" then return false end

    TriggerClientEvent("jpr-phonesystem:client:customnotification", source, {
        app   = "Custom",
        title = notification.title or "",
        img   = notification.icon or "",
        text  = notification.content or notification.message or "",
        time  = notification.timeout or 3000,
    })

    return true
end

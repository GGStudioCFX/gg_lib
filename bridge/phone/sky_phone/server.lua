gg.phone = gg.phone or {}

-- On the server sky_phone answers only lb-phone's number lookups, which is all
-- the lb-phone bridge needs apart from mail.
local PATH = "bridge/phone/lb-phone/server.lua"
local NAME = "sky_phone"

local source = LoadResourceFile("gg_lib", PATH)

if not source or source == "" then
    print("^1[gg_lib] sky_phone bridge could not read " .. PATH .. "^0")
    return
end

local env = setmetatable({ GG_PHONE_EXPORT = "lb-phone", GG_PHONE_RESOURCE = NAME }, {
    __index = _ENV,
    __newindex = function(_, key, value) _ENV[key] = value end,
})

local chunk, err = load(source, ("@@gg_lib/%s"):format(PATH), "t", env)

if not chunk then
    print("^1[gg_lib] sky_phone bridge could not compile " .. PATH .. ": " .. tostring(err) .. "^0")
    return
end

chunk()

-- sky_phone exports no way for another resource to send mail, under either name.
local warned = false

gg.phone.mail = function()
    if not warned then
        warned = true
        gg.print.warn(("%s cannot be sent mail by another resource; gg.phone.mail returns false on it"):format(NAME))
    end

    return false
end

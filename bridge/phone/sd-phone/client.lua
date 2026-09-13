gg.phone = gg.phone or {}

-- sd-phone ships an lb-phone compatibility layer that is on by default: it
-- answers exports['lb-phone'], serves lb-phone custom apps unmodified, and
-- declares provide 'lb-phone'. provide does not make GetResourceState report
-- lb-phone as started, which is why this folder exists under sd-phone's own
-- name -- but the calls still go to the export sd-phone documents, lb-phone.
local PATH = "bridge/phone/lb-phone/client.lua"

local source = LoadResourceFile("gg_lib", PATH)

if not source or source == "" then
    print("^1[gg_lib] sd-phone bridge could not read " .. PATH .. "^0")
    return
end

local env = setmetatable({ GG_PHONE_EXPORT = "lb-phone", GG_PHONE_RESOURCE = "sd-phone" }, {
    __index = _ENV,
    __newindex = function(_, key, value) _ENV[key] = value end,
})

local chunk, err = load(source, ("@@gg_lib/%s"):format(PATH), "t", env)

if not chunk then
    print("^1[gg_lib] sd-phone bridge could not compile " .. PATH .. ": " .. tostring(err) .. "^0")
    return
end

chunk()

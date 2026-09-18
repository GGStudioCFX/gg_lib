gg.phone = gg.phone or {}

-- sky_phone answers lb-phone's client exports itself: it declares provide
-- 'lb-phone' and registers the lb-phone export names, and it serves lb-phone
-- custom apps unmodified. So, as for sd-phone, this folder runs the lb-phone
-- bridge with only the resource name swapped.
local PATH = "bridge/phone/lb-phone/client.lua"
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

-- Game keys stay live while the phone is open (its AllowMovement, on by default),
-- and a field focused inside an app's frame is not one sky_phone recognises, so
-- typing into an app would reach the game. The app reports its focus here and
-- the phone holds game input for the duration. Game input is only handed back
-- if it was on before, so a server that turned movement off keeps it off. The
-- phone drops the hold itself when it closes or this resource stops.
local gameInput, holding = nil, false

AddEventHandler("sky_phone:client:cameraFocusApplied", function(focus)
    if type(focus) == "table" then gameInput = focus.gameInput == true end
end)

AddEventHandler("sky_phone:client:phoneToggled", function()
    holding = false
end)

gg.phone.app.focus = function(focused)
    if GetResourceState(NAME) ~= "started" then return false end

    if focused then
        if holding or gameInput == false then return true end

        local ok, held = pcall(function() return exports[NAME]:SetPhoneGameInputEnabled(false) end)

        holding = ok and held == true and gameInput == true

        return ok and held == true
    end

    if not holding then return true end

    holding = false

    local ok, restored = pcall(function() return exports[NAME]:SetPhoneGameInputEnabled(true) end)

    return ok and restored == true
end

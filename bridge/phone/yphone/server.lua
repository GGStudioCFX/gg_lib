gg.phone = gg.phone or {}

local PATH = "bridge/phone/yseries/server.lua"

local source = LoadResourceFile("gg_lib", PATH)

if not source or source == "" then
    print("^1[gg_lib] yphone bridge could not read " .. PATH .. "^0")
    return
end

local env = setmetatable({ GG_PHONE_EXPORT = "yphone" }, {
    __index = _ENV,
    __newindex = function(_, key, value) _ENV[key] = value end,
})

local chunk, err = load(source, ("@@gg_lib/%s"):format(PATH), "t", env)

if not chunk then
    print("^1[gg_lib] yphone bridge could not compile " .. PATH .. ": " .. tostring(err) .. "^0")
    return
end

chunk()

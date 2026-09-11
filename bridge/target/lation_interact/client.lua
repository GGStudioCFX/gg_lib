gg.target = gg.target or {}

-- lation_interact answers every ox_target export -- named removal, distances,
-- canInteract signatures, dispatch payloads -- so the ox_target bridge is the
-- bridge, pointed at lation_interact's own export name rather than the
-- ox_target alias, which a server still running the real ox_target would
-- answer instead.
local PATH = "bridge/target/ox_target/client.lua"

local source = LoadResourceFile("gg_lib", PATH)

if not source or source == "" then
    print("^1[gg_lib] lation_interact bridge could not read " .. PATH .. "^0")
    return
end

local env = setmetatable({ GG_TARGET_EXPORT = "lation_interact" }, {
    __index = _ENV,
    __newindex = function(_, key, value) _ENV[key] = value end,
})

local chunk, err = load(source, ("@@gg_lib/%s"):format(PATH), "t", env)

if not chunk then
    print("^1[gg_lib] lation_interact bridge could not compile " .. PATH .. ": " .. tostring(err) .. "^0")
    return
end

chunk()

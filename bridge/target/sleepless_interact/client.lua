gg.target = gg.target or {}

local PATH = "bridge/target/ox_target/client.lua"

local source = LoadResourceFile("gg_lib", PATH)

if not source or source == "" then
    print("^1[gg_lib] sleepless_interact bridge could not read " .. PATH .. "^0")
    return
end

local chunk, err = load(source, ("@@gg_lib/%s"):format(PATH), "t", _ENV)

if not chunk then
    print("^1[gg_lib] sleepless_interact bridge could not compile " .. PATH .. ": " .. tostring(err) .. "^0")
    return
end

chunk()

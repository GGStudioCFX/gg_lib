
local KNOWN = { race = true, taxi = true }

GGCallback.register("gg_lib:waypoints:defaults", function()
    local out = {}

    for style in pairs(KNOWN) do
        out[style] = GenericSettings.get(("waypoints.%s"):format(style))
    end

    return out
end)

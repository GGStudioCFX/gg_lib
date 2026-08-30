
GG_GROUPS = GG_GROUPS or { held = {}, watchers = {} }

local function tell(kind, group)
    for index = 1, #GG_GROUPS.watchers do
        local ok, err = pcall(GG_GROUPS.watchers[index], kind, group)

        if not ok then print(("[gg_lib] a group watcher errored: %s"):format(tostring(err))) end
    end
end

RegisterNetEvent("gg_lib:group:sync", function(kind, group)
    if type(kind) ~= "string" then return end

    GG_GROUPS.held[kind] = group

    tell(kind, group)
end)

function GG_GROUPS.current(kind)
    return GG_GROUPS.held[kind]
end

function GG_GROUPS.watch(fn)
    if type(fn) ~= "function" then return end

    GG_GROUPS.watchers[#GG_GROUPS.watchers + 1] = fn
end

function GG_GROUPS.refresh(kind)
    if type(kind) ~= "string" then return end

    TriggerServerEvent("gg_lib:group:ask", kind)
end

exports("ggGroupCurrent", function(kind)
    return GG_GROUPS.current(kind)
end)

exports("ggGroupRefresh", function(kind)
    GG_GROUPS.refresh(kind)
end)

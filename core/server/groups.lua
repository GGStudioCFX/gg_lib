gg = gg or {}
gg.print = gg.print or { error = print, warn = print, log = print }

local DEFAULT_MAX = 4

local kinds = {}

local groups = {}

local seats = {}

local nextId = 0

local function ceiling(kind, asked)
    local declared = kinds[kind]
    local top = (declared and declared.max) or DEFAULT_MAX

    asked = tonumber(asked)

    if asked and asked >= 1 and asked <= top then return math.floor(asked) end

    return top
end

local function count(group)
    local total = 0

    for _ in pairs(group.members) do total = total + 1 end

    return total
end

local function describe(group)
    if not group then return nil end

    local members = {}

    for source, member in pairs(group.members) do
        members[#members + 1] = {
            source = source,
            name   = GetPlayerName(source) or ("Player %s"):format(source),
            leader = source == group.leader,
            joined = member.joined,
            meta   = member.meta,
        }
    end

    table.sort(members, function(a, b) return a.joined < b.joined end)

    return {
        id      = group.id,
        kind    = group.kind,
        leader  = group.leader,
        max     = group.max,
        count   = #members,
        full    = #members >= group.max,
        meta    = group.meta,
        members = members,
    }
end

local function sync(group, alsoTell)
    local payload = describe(group)

    if group then
        for source in pairs(group.members) do
            TriggerClientEvent("gg_lib:group:sync", source, group.kind, payload)
        end
    end

    if alsoTell then
        TriggerClientEvent("gg_lib:group:sync", alsoTell, group.kind, nil)
    end
end

local function seatOf(source, kind)
    return seats[source] and seats[source][kind] or nil
end

local function unseat(source, kind)
    if seats[source] then seats[source][kind] = nil end
end

local function seat(source, kind, id)
    seats[source] = seats[source] or {}
    seats[source][kind] = id
end

local function drop(source, kind)
    local id = seatOf(source, kind)

    if not id then return false end

    local group = groups[id]

    unseat(source, kind)

    if not group then return false end

    group.members[source] = nil

    local left = describe(group)

    if left.count == 0 then
        groups[id] = nil

        TriggerClientEvent("gg_lib:group:sync", source, kind, nil)

        return true
    end

    if group.leader == source then group.leader = left.members[1].source end

    sync(group, source)

    return true
end

exports("ggGroupDefine", function(kind, opts)
    if type(kind) ~= "string" or kind == "" then return false end

    opts = type(opts) == "table" and opts or {}

    local max = tonumber(opts.max)

    kinds[kind] = {
        kind  = kind,
        label = type(opts.label) == "string" and opts.label or kind,
        max   = (max and max >= 1) and math.floor(max) or DEFAULT_MAX,
        meta  = type(opts.meta) == "table" and opts.meta or {},
    }

    return true
end)

exports("ggGroupKinds", function()
    local out = {}

    for _, entry in pairs(kinds) do out[#out + 1] = entry end

    table.sort(out, function(a, b) return a.kind < b.kind end)

    return out
end)

exports("ggGroupCreate", function(source, kind, opts)
    if type(kind) ~= "string" or kind == "" then return nil, "no kind" end
    if not GetPlayerName(source) then return nil, "no player" end

    opts = type(opts) == "table" and opts or {}

    drop(source, kind)

    nextId = nextId + 1

    local id = ("%s:%d"):format(kind, nextId)

    groups[id] = {
        id      = id,
        kind    = kind,
        leader  = source,
        max     = ceiling(kind, opts.max),
        meta    = type(opts.meta) == "table" and opts.meta or {},
        members = { [source] = { joined = os.time(), meta = type(opts.memberMeta) == "table" and opts.memberMeta or {} } },
    }

    seat(source, kind, id)
    sync(groups[id])

    return id
end)

exports("ggGroupJoin", function(source, id, meta)
    local group = groups[id]

    if not group then return false, "no group" end
    if not GetPlayerName(source) then return false, "no player" end
    if group.members[source] then return true end
    if count(group) >= group.max then return false, "full" end

    drop(source, group.kind)

    group.members[source] = { joined = os.time(), meta = type(meta) == "table" and meta or {} }

    seat(source, group.kind, id)
    sync(group)

    return true
end)

exports("ggGroupLeave", function(source, kind)
    return drop(source, kind)
end)

exports("ggGroupKick", function(source, target, kind)
    local id = seatOf(source, kind)
    local group = id and groups[id]

    if not group then return false, "no group" end
    if group.leader ~= source then return false, "not the leader" end
    if target == source then return false, "kicking yourself is leaving" end
    if not group.members[target] then return false, "not a member" end

    drop(target, kind)

    return true
end)

exports("ggGroupDisband", function(source, kind)
    local id = seatOf(source, kind)
    local group = id and groups[id]

    if not group then return false, "no group" end
    if group.leader ~= source then return false, "not the leader" end

    for member in pairs(group.members) do
        unseat(member, kind)

        TriggerClientEvent("gg_lib:group:sync", member, kind, nil)
    end

    groups[id] = nil

    return true
end)

exports("ggGroupSetLeader", function(source, target, kind)
    local id = seatOf(source, kind)
    local group = id and groups[id]

    if not group then return false, "no group" end
    if group.leader ~= source then return false, "not the leader" end
    if not group.members[target] then return false, "not a member" end

    group.leader = target

    sync(group)

    return true
end)

exports("ggGroupSetMeta", function(id, key, value)
    local group = groups[id]

    if not group or type(key) ~= "string" then return false end

    group.meta[key] = value

    sync(group)

    return true
end)

exports("ggGroupSetMemberMeta", function(id, source, key, value)
    local group = groups[id]

    if not group or not group.members[source] or type(key) ~= "string" then return false end

    group.members[source].meta[key] = value

    sync(group)

    return true
end)

exports("ggGroupGet", function(id)
    return describe(groups[id])
end)

exports("ggGroupOf", function(source, kind)
    return describe(groups[seatOf(source, kind) or ""])
end)

exports("ggGroupList", function(kind)
    local out = {}

    for _, group in pairs(groups) do
        if not kind or group.kind == kind then out[#out + 1] = describe(group) end
    end

    table.sort(out, function(a, b) return a.id < b.id end)

    return out
end)

AddEventHandler("playerDropped", function()
    local held = seats[source]

    if not held then return end

    for kind in pairs(held) do drop(source, kind) end

    seats[source] = nil
end)

RegisterNetEvent("gg_lib:group:ask", function(kind)
    TriggerClientEvent("gg_lib:group:sync", source, kind, describe(groups[seatOf(source, kind) or ""]))
end)

GGCallback.register("gg_lib:groups:fetch", function(source)
    if not (Admins and Admins.canView and Admins.canView(source)) then
        print(("^3[gg_lib] blocked groups fetch from %s^0"):format(
            (Admins and Admins.actor and Admins.actor(source)) or tostring(source)))

        return false
    end

    local live = {}

    for _, group in pairs(groups) do live[#live + 1] = describe(group) end

    table.sort(live, function(a, b) return a.id < b.id end)

    local declared = {}

    for _, entry in pairs(kinds) do declared[#declared + 1] = entry end

    table.sort(declared, function(a, b) return a.kind < b.kind end)

    return true, { groups = live, kinds = declared }
end)

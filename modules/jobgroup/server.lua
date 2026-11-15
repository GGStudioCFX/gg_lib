--------------------------------------------------
-- MARK: Job Groups
--------------------------------------------------

-- gg.jobgroup: the one group every GG job shares (kind "gg_jobs", four at most) and the
-- invite rules each job's tablet follows. Any resource drives the same group through
-- these calls: a job's Groups page, a city hall, a phone app. gg_lib core holds the group
-- (ggGroup* exports) and syncs its members' clients (gg_lib:group:sync), so a group made
-- in one place is the same group everywhere.
--
-- The group's meta carries two keys every job keeps:
--   invites  = { ["<target source>"] = { from = source, at = os.time(), job = label, max = n } }
--   activity = { job = resource, label = job name, detail = what it runs, at = os.time() }
-- A set activity means the group is busy in that job: nobody invites or joins until it
-- clears, and only that job ends it. knowledge/source/jobs-kit.md is the full contract.
--
-- Calls answer { ok = true, ... } or { ok = false, error = code }. Codes: not_found, self,
-- not_leader, group_busy (with label), full, target_busy, already_invited, invite_gone,
-- leave_first, too_soon, failed. kick/promote/disband are the leader's; a kicked or
-- disbanded member's client gets "gg_jobs:kicked" { group, from, disbanded? }.

gg.jobgroup = gg.jobgroup or {}

local jobgroup = gg.jobgroup
local core = exports.gg_lib

jobgroup.KIND       = "gg_jobs"
jobgroup.MAX        = 4  -- a GG job group is at most four workers (owner 2026-11-06)
jobgroup.INVITE_TTL = 300
jobgroup.INVITE_GAP = 3  -- seconds between one player's invites

local KIND = jobgroup.KIND

local function call(name, ...)
    local ok, a, b = pcall(core[name], core, ...)

    if not ok then
        gg.print.warn(("gg_lib %s failed: %s"):format(name, tostring(a)))

        return nil, "failed"
    end

    return a, b
end

--- Declares the kind (safe to call again; gg_lib keeps the first definition).
function jobgroup.define()
    pcall(function() core:ggGroupDefine(KIND, { max = jobgroup.MAX, label = "Job Group" }) end)
end

--- The shared group a player is in, or nil.
function jobgroup.of(source)
    return call("ggGroupOf", source, KIND)
end

--- A group by its id, or nil.
function jobgroup.get(id)
    return type(id) == "string" and call("ggGroupGet", id) or nil
end

--- Every group of the kind.
function jobgroup.list()
    return call("ggGroupList", KIND) or {}
end

--- The members' server ids, leader included.
function jobgroup.sources(group)
    local out = {}

    for index, member in ipairs(group and group.members or {}) do out[index] = member.source end

    return out
end

local function has(list, value)
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end

    return false
end

--- What the group is busy with in some job, or nil.
function jobgroup.activity(group)
    local activity = group and group.meta and group.meta.activity

    return type(activity) == "table" and activity or nil
end

--- The group's live invites: { ["<target source>"] = entry }.
function jobgroup.invites(group)
    local now, out = os.time(), {}
    local stored = group and group.meta and group.meta.invites

    if type(stored) ~= "table" then return out end

    for target, entry in pairs(stored) do
        if type(entry) == "table" and (tonumber(entry.at) or 0) + jobgroup.INVITE_TTL > now then out[tostring(target)] = entry end
    end

    return out
end

local function setInvites(group, invites)
    call("ggGroupSetMeta", group.id, "invites", next(invites) and invites or nil)
end

--- The invites waiting for a player: { { group, from, job, at } }.
function jobgroup.invitesFor(source)
    local out = {}
    local key = tostring(source)

    for _, group in ipairs(jobgroup.list()) do
        local entry = jobgroup.invites(group)[key]

        if entry and not has(jobgroup.sources(group), source) and GetPlayerName(entry.from) then
            out[#out + 1] = { group = group.id, from = entry.from, job = entry.job or "", at = entry.at }
        end
    end

    return out
end

--- A player already with others, or whose group is busy in a job, takes no invite.
function jobgroup.busy(target)
    local group = jobgroup.of(target)

    return group ~= nil and (group.count > 1 or jobgroup.activity(group) ~= nil)
end

local lastInvite = {}

--- Invites any online player by server id (no distance rule: a city hall or phone can
--- invite from anywhere). opts: job (the label the invite shows), max (the cap, at most MAX).
--- Makes the inviter a group of one first when they have none.
function jobgroup.invite(source, target, opts)
    opts = type(opts) == "table" and opts or {}
    target = tonumber(target)

    if not target or not GetPlayerName(target) then return { ok = false, error = "not_found" } end
    if target == source then return { ok = false, error = "self" } end

    local now = os.time()

    if lastInvite[source] and now - lastInvite[source] < jobgroup.INVITE_GAP then return { ok = false, error = "too_soon" } end

    local max = math.max(2, math.min(jobgroup.MAX, math.floor(tonumber(opts.max) or jobgroup.MAX)))
    local group = jobgroup.of(source)

    if group and group.leader ~= source then return { ok = false, error = "not_leader" } end
    if group and jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end
    if group and group.count >= max then return { ok = false, error = "full" } end
    if jobgroup.busy(target) then return { ok = false, error = "target_busy" } end

    if group and jobgroup.invites(group)[tostring(target)] then return { ok = false, error = "already_invited" } end

    if not group then
        jobgroup.define()

        group = jobgroup.get(call("ggGroupCreate", source, KIND, { max = jobgroup.MAX }))

        if not group then return { ok = false, error = "failed" } end
    end

    local invites = jobgroup.invites(group)

    invites[tostring(target)] = { from = source, at = now, job = tostring(opts.job or ""), max = max }
    setInvites(group, invites)
    lastInvite[source] = now

    -- Every GG job's tablet (and any app) listens for this and refreshes its Groups page.
    TriggerClientEvent("gg_jobs:invite", target, { group = group.id, from = GetPlayerName(source), job = tostring(opts.job or "") })

    return { ok = true, group = group.id }
end

--- Takes an invite. A player alone in an idle group of one leaves it for the new one.
function jobgroup.join(source, id)
    local group = jobgroup.get(id)
    local invites = group and jobgroup.invites(group)
    local entry = invites and invites[tostring(source)]

    if not entry then return { ok = false, error = "invite_gone" } end
    if jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end
    if group.full or group.count >= math.min(jobgroup.MAX, tonumber(entry.max) or jobgroup.MAX) then return { ok = false, error = "full" } end

    local mine = jobgroup.of(source)

    if mine and mine.id ~= group.id and (mine.count > 1 or jobgroup.activity(mine)) then return { ok = false, error = "leave_first" } end

    if not call("ggGroupJoin", source, group.id, {}) then return { ok = false, error = "full" } end

    invites[tostring(source)] = nil
    setInvites(group, invites)

    return { ok = true, group = group.id, leader = group.leader }
end

--- Turns an invite down.
function jobgroup.decline(source, id)
    local group = jobgroup.get(id)

    if not group then return { ok = true } end

    local invites = jobgroup.invites(group)

    invites[tostring(source)] = nil
    setInvites(group, invites)

    return { ok = true, group = group.id, leader = group.leader }
end

--- Leaves the group. A group busy in a job is left through that job, so its route ends right.
function jobgroup.leave(source)
    local group = jobgroup.of(source)

    if not group then return { ok = false, error = "not_found" } end
    if jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end

    call("ggGroupLeave", source, KIND)

    return { ok = true, group = group.id }
end

local function inGroup(group, target)
    return group ~= nil and has(jobgroup.sources(group), target)
end

--- The leader removes a member. A group busy in a job changes through that job.
function jobgroup.kick(source, target)
    target = tonumber(target)

    local group = jobgroup.of(source)

    if not group then return { ok = false, error = "not_found" } end
    if group.leader ~= source then return { ok = false, error = "not_leader" } end
    if target == source then return { ok = false, error = "self" } end
    if not inGroup(group, target) then return { ok = false, error = "not_found" } end
    if jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end

    if not call("ggGroupKick", source, target, KIND) then return { ok = false, error = "failed" } end

    TriggerClientEvent("gg_jobs:kicked", target, { group = group.id, from = GetPlayerName(source) })

    return { ok = true, group = group.id }
end

--- The leader hands the lead to another member.
function jobgroup.promote(source, target)
    target = tonumber(target)

    local group = jobgroup.of(source)

    if not group then return { ok = false, error = "not_found" } end
    if group.leader ~= source then return { ok = false, error = "not_leader" } end
    if target == source then return { ok = false, error = "self" } end
    if not inGroup(group, target) then return { ok = false, error = "not_found" } end
    if jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end

    if not call("ggGroupSetLeader", source, target, KIND) then return { ok = false, error = "failed" } end

    return { ok = true, group = group.id, leader = target }
end

--- The leader ends the group for everyone in it.
function jobgroup.disband(source)
    local group = jobgroup.of(source)

    if not group then return { ok = false, error = "not_found" } end
    if group.leader ~= source then return { ok = false, error = "not_leader" } end
    if jobgroup.activity(group) then return { ok = false, error = "group_busy", label = jobgroup.activity(group).label or "" } end

    local members = jobgroup.sources(group)

    if not call("ggGroupDisband", source, KIND) then return { ok = false, error = "failed" } end

    for _, member in ipairs(members) do
        if member ~= source then TriggerClientEvent("gg_jobs:kicked", member, { group = group.id, from = GetPlayerName(source), disbanded = true }) end
    end

    return { ok = true, group = group.id }
end

--- What a city hall or phone shows: the group, its activity and the invites waiting.
function jobgroup.summary(source)
    local group = jobgroup.of(source)
    local out = { group = false, invites = jobgroup.invitesFor(source) }

    if group then
        local members = {}

        for index, member in ipairs(group.members or {}) do
            members[index] = { source = member.source, leader = member.leader == true, name = GetPlayerName(member.source) }
        end

        out.group = {
            id       = group.id,
            leader   = group.leader,
            count    = group.count,
            max      = jobgroup.MAX,
            members  = members,
            activity = jobgroup.activity(group) or false,
        }
    end

    return out
end

AddEventHandler("playerDropped", function()
    lastInvite[source] = nil
end)

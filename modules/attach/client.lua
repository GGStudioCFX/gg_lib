gg.attach = gg.attach or {}

local RESOURCE = GetCurrentResourceName()

local waiting = {}
local accepted = {}
local sequence = 0

AddEventHandler("gg_lib:attach:placeAccepted", function(resource, id)
    if resource ~= RESOURCE then return end

    accepted[id] = true
end)

AddEventHandler("gg_lib:attach:placeResult", function(resource, id, result)
    if resource ~= RESOURCE then return end

    local answer = waiting[id]
    if not answer then return end

    waiting[id] = nil
    accepted[id] = nil

    answer:resolve(result)
end)

local function request(options)
    sequence = sequence + 1

    local id = sequence
    local answer = promise.new()

    waiting[id] = answer

    TriggerEvent("gg_lib:attach:place", RESOURCE, id, options)

    SetTimeout(3000, function()
        if not waiting[id] or accepted[id] then return end

        waiting[id] = nil

        answer:resolve("Restart gg_lib -- its placement editor did not answer")
    end)

    SetTimeout(900000, function()
        if not waiting[id] then return end

        waiting[id] = nil
        accepted[id] = nil

        answer:resolve(nil)
    end)

    return Citizen.Await(answer)
end

function gg.attach.placeVehicleProps(options)
    if type(options) ~= "table" then return "nothing to place" end

    return request(options)
end

--------------------------------------------------
-- MARK: Rotation orders
--------------------------------------------------

-- The editor turns things in GTA's rotation order 2. A script that attaches
-- with another order (AttachEntityToEntity's rotationOrder) passes rot_order,
-- and its angles are converted on the way in and out, so the pose it saves is
-- the pose it sees. Each order names the axis applied first, second, third.

local ORDERS = {
    [0] = { "x", "y", "z" },
    [1] = { "x", "z", "y" },
    [2] = { "y", "x", "z" },
    [3] = { "y", "z", "x" },
    [4] = { "z", "x", "y" },
    [5] = { "z", "y", "x" },
}

local EDITOR_ORDER = 2
local AXIS = { x = 1, y = 2, z = 3 }
local EVEN = { xyz = true, yzx = true, zxy = true }

local function axisMatrix(axis, degrees)
    local r = math.rad(tonumber(degrees) or 0.0)
    local c, s = math.cos(r), math.sin(r)

    if axis == "x" then return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
    if axis == "y" then return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end

    return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end

local function multiply(a, b)
    local out = {}

    for row = 1, 3 do
        out[row] = {}

        for column = 1, 3 do
            out[row][column] = a[row][1] * b[1][column] + a[row][2] * b[2][column] + a[row][3] * b[3][column]
        end
    end

    return out
end

local function toMatrix(rot, order)
    local axes = ORDERS[order]
    local matrix = axisMatrix(axes[1], rot[axes[1]])

    matrix = multiply(axisMatrix(axes[2], rot[axes[2]]), matrix)

    return multiply(axisMatrix(axes[3], rot[axes[3]]), matrix)
end

local function fromMatrix(m, order)
    local axes = ORDERS[order]
    local i, j, k = AXIS[axes[1]], AXIS[axes[2]], AXIS[axes[3]]
    local sign = EVEN[axes[1] .. axes[2] .. axes[3]] and 1 or -1
    local edge = -sign * m[k][i]

    local first, second, third

    second = math.asin(math.max(-1.0, math.min(1.0, edge)))

    if math.abs(edge) < 0.9999999 then
        first = math.atan(sign * m[k][j], m[k][k])
        third = math.atan(sign * m[j][i], m[i][i])
    else
        -- Straight up or down the middle axis: the first and last turn the
        -- same way, so it all goes on the first.
        first = math.atan(-sign * m[j][k], m[j][j])
        third = 0.0
    end

    local out = { [axes[1]] = math.deg(first), [axes[2]] = math.deg(second), [axes[3]] = math.deg(third) }

    return { x = out.x, y = out.y, z = out.z }
end

local function vec3(value)
    value = type(value) == "table" and value or {}

    return { x = tonumber(value.x) or 0.0, y = tonumber(value.y) or 0.0, z = tonumber(value.z) or 0.0 }
end

--- rot in rotation order `from`, as the same turn in order `to`.
function gg.attach.convertRotation(rot, from, to)
    rot = vec3(rot)
    from, to = math.floor(tonumber(from) or EDITOR_ORDER), math.floor(tonumber(to) or EDITOR_ORDER)

    if from == to or not ORDERS[from] or not ORDERS[to] then return rot end

    return fromMatrix(toMatrix(rot, from), to)
end

--------------------------------------------------
-- MARK: Placing anything on anything
--------------------------------------------------

--- Opens the placement editor on one thing attached to another and waits.
---
---   subject = { kind = "prop" | "ped", model, dead = true, anim = { dict, name } }
---   target  = { kind = "vehicle" | "ped" | "prop", model, bone, anim = { dict, name, flag }, properties }
---     vehicle: model is the vehicle, bone a bone name ("boot") or index (0 = its origin)
---     ped:     the player is the target, bone a ped bone id, anim what they play
---     prop:    model is the prop it sits on
---   pos, rot  the pose to start from, offsets from the bone and degrees
---   rot_order the rotationOrder the script attaches with (default 2)
---   choices  { { id, label, model, pos, rot }, ... } to switch between in
---            the editor, each keeping its own pose; choice = which first
---   choice_label  what the choices are, for the dropdown ("Animal and slot")
---   title, label  the panel's heading and the line under it
---
--- Returns { choice, model, pos, rot, poses } when saved, nil when discarded,
--- or a string saying why it could not open. choice, pos and rot are the one
--- on screen at save; poses = { [id] = { pos, rot } } every choice that was
--- moved, so one session can set them all.
function gg.attach.place(options)
    if type(options) ~= "table" then return "nothing to place" end

    local subject = type(options.subject) == "table" and options.subject or {}
    local target  = type(options.target) == "table" and options.target or {}
    local order   = math.floor(tonumber(options.rot_order) or EDITOR_ORDER)

    if not ORDERS[order] then return ("rotation order %s does not exist"):format(tostring(options.rot_order)) end

    local function toEditor(rot) return gg.attach.convertRotation(rot, order, EDITOR_ORDER) end

    local kits, models = {}, {}

    if type(options.choices) == "table" and #options.choices > 0 then
        for index, choice in ipairs(options.choices) do
            local id = tostring(choice.id or index)

            models[id] = choice.model
            kits[#kits + 1] = {
                id    = id,
                label = tostring(choice.label or choice.model or id),
                props = { { model = choice.model } },
                pos   = choice.pos and vec3(choice.pos) or nil,
                rot   = choice.rot and toEditor(choice.rot) or nil,
            }
        end
    elseif type(subject.model) == "string" and subject.model ~= "" then
        models[subject.model] = subject.model
        kits[1] = { id = subject.model, label = options.label or subject.model, props = { { model = subject.model } } }
    else
        return "nothing to place"
    end

    local result = request({
        title        = options.title or "Placement",
        subject      = options.label,
        vehicle      = target.kind == "vehicle" and target.model or nil,
        properties   = target.properties,
        subject_kind = subject.kind == "ped" and "ped" or "prop",
        dead         = subject.dead == true,
        subject_anim = subject.anim,
        target_kind  = target.kind or "vehicle",
        target_model = target.model,
        bone         = target.bone,
        player_anim  = target.anim,
        pos          = vec3(options.pos),
        rot          = toEditor(options.rot),
        kits         = kits,
        kit          = options.choice and tostring(options.choice) or kits[1].id,
        choice_label = options.choice_label,
        custom       = false,
        per_choice   = true,
    })

    if type(result) ~= "table" then return result end

    local poses = {}

    for id, pose in pairs(type(result.poses) == "table" and result.poses or {}) do
        poses[id] = { pos = vec3(pose.pos), rot = gg.attach.convertRotation(pose.rot, EDITOR_ORDER, order) }
    end

    return {
        choice = result.kit,
        model  = models[result.kit] or result.kit,
        pos    = vec3(result.pos),
        rot    = gg.attach.convertRotation(result.rot, EDITOR_ORDER, order),
        poses  = poses,
    }
end

function gg.attach.editor()
    return exports.gg_lib:ggAttachEditor()
end

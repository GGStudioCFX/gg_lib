local payout = gg.payout

-- MARK: Client: the table and the hand-over
--
-- Everything on the table is local to the worker's own game: the table and the pay on it
-- are client-only objects, because only the worker it belongs to sees their own pay. The
-- worker's own moves are ordinary scripted anims, so the players around see them.
-- A job calls gg.payout.setup once, gg.payout.table(id, coords) for every table depot,
-- and gg.payout.fromPed(id, ped, scene) from its depot ped's target.

local RESOURCE = GetCurrentResourceName()

local RENDER_IN  = 45.0
local RENDER_OUT = 55.0

-- The grab, newest first: a one-hand grab at waist height (Drug Wars, build 2802), then the
-- base game's take-from-a-hand for older builds. take = when the hand closes on the pay,
-- stash = when it goes into the pocket, length = when the worker is free again.
local GRABS = {
    { dict = "anim@scripted@player@freemode@gen_grab@male@", clip = "med_rh", take = 0.55, stash = 1.05, length = 1.45 },
    { dict = "mp_common", clip = "givetake1_b", take = 0.45, stash = 1.0, length = 1.5 },
}

local GIVE = { dict = "mp_common", giver = "givetake1_a", taker = "givetake1_b", pass = 0.9, length = 2.1 }

-- Holding the closed case: the standard one-hand briefcase hold.
local CARRY = {
    dict     = "missheistdocksprep1hold_cellphone",
    clip     = "static",
    bone     = 57005,
    offset   = { 0.10, 0.0, 0.0 },
    rotation = { 0.0, 280.0, 53.0 },
    seconds  = 60,
    distance = 40.0,
}

local HAND_BONE = 28422 -- PH_R_Hand: what a bundle or an envelope is held by

-- Where the worker stands to take the pay: this far out from the table's nearest edge.
local STAND_OFF = 0.42

local options = {}
local state = {
    owed     = { money = 0, experience = 0, count = 0 },
    busy     = false,
    carrying = nil,
}
local points = {}

--------------------------------------------------
-- MARK: Helpers
--------------------------------------------------

local function exists(model)
    return IsModelInCdimage(joaat(model))
end

-- The newest table this build has.
local function tableDef()
    for _, def in ipairs(payout.TABLES) do
        if exists(def.model) then return def end
    end
end

-- A pile's model on this build, and how far it is lifted onto the top.
local function pileModel(pile)
    if exists(pile.model) then return pile.model, pile.lift end

    local fallback = pile.fallback

    if fallback and exists(fallback.model) then return fallback.model, fallback.lift end
end

local function spawn(model, at, heading, solid)
    if not exists(model) or not gg.util.loadModel(model) then return nil end

    local hash = joaat(model)
    local object = CreateObject(hash, at.x + 0.0, at.y + 0.0, at.z + 0.0, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not object or object == 0 then return nil end

    SetEntityHeading(object, (heading or 0.0) + 0.0)
    FreezeEntityPosition(object, true)

    if not solid then SetEntityCollision(object, false, false) end

    return object
end

local function remove(object)
    if object and DoesEntityExist(object) then
        DetachEntity(object, false, false)
        DeleteObject(object)
    end
end

local function grabClip()
    for _, grab in ipairs(GRABS) do
        if DoesAnimDictExist(grab.dict) and gg.util.loadAnimDict(grab.dict) then return grab end
    end
end

local function caseFrom()
    local value = type(options.caseFrom) == "function" and options.caseFrom() or options.caseFrom

    return math.max(1, math.floor(tonumber(value) or 5000))
end

local function owesSomething()
    return state.owed.count > 0 or state.owed.money > 0 or state.owed.experience > 0
end

local function canCollect()
    if state.busy or state.carrying then return false end
    if not owesSomething() then return false end
    if type(options.canCollect) == "function" and not options.canCollect() then return false end

    return true
end

local function refuse(code)
    if type(options.refused) == "function" then pcall(options.refused, code) end
end

local function collected(result)
    if type(options.collected) == "function" then pcall(options.collected, result) end
end

local function holdInHand(ped, model, bone, offset, rotation)
    local object = spawn(model, GetEntityCoords(ped), 0.0, false)
    if not object then return nil end

    FreezeEntityPosition(object, false)

    offset = offset or { 0.0, 0.0, 0.0 }
    rotation = rotation or { 0.0, 0.0, 0.0 }

    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, bone or HAND_BONE),
        offset[1], offset[2], offset[3], rotation[1], rotation[2], rotation[3],
        true, true, false, false, 2, true)

    return object
end

--------------------------------------------------
-- MARK: Carrying the case off
--------------------------------------------------

local function stow()
    local carry = state.carrying
    if not carry then return end

    state.carrying = nil

    remove(carry.object)

    local ped = PlayerPedId()

    if IsEntityPlayingAnim(ped, CARRY.dict, CARRY.clip, 3) then StopAnimTask(ped, CARRY.dict, CARRY.clip, 2.0) end
end

-- The case stays in hand until the worker drives off, walks away or the time is up.
local function carryCase(from)
    stow()

    local ped = PlayerPedId()
    local object = holdInHand(ped, payout.PARTS.carry, CARRY.bone, CARRY.offset, CARRY.rotation)

    if not object then return end

    local animated = gg.util.loadAnimDict(CARRY.dict)

    if animated then TaskPlayAnim(ped, CARRY.dict, CARRY.clip, 4.0, -4.0, -1, 49, 0, false, false, false) end

    local carry = { object = object, from = from, started = GetGameTimer() }

    state.carrying = carry

    CreateThread(function()
        while state.carrying == carry do
            Wait(250)

            local me = PlayerPedId()
            local done = IsPedInAnyVehicle(me, true)
                or IsEntityDead(me)
                or IsPedSwimming(me)
                or GetGameTimer() - carry.started > CARRY.seconds * 1000
                or #(GetEntityCoords(me) - carry.from) > CARRY.distance
                or not DoesEntityExist(carry.object)

            if done then
                stow()
            elseif animated and not IsEntityPlayingAnim(me, CARRY.dict, CARRY.clip, 3) and not IsPedRagdoll(me) then
                TaskPlayAnim(me, CARRY.dict, CARRY.clip, 4.0, -4.0, -1, 49, 0, false, false, false)
            end
        end
    end)
end

--------------------------------------------------
-- MARK: The table
--------------------------------------------------

local function clearCash(point)
    for _, object in ipairs(point.cash) do remove(object) end

    point.cash = {}
end

-- One pile for every finished job not yet collected. Only what changed is touched.
local function render(point)
    if not point.table or not DoesEntityExist(point.table) or point.frozen then return end

    point.rendering = (point.rendering or 0) + 1

    local mine = point.rendering
    local want = payout.piles(state.owed)

    while #point.cash > want do
        remove(table.remove(point.cash))
    end

    local heading = GetEntityHeading(point.table)
    local top = point.def.top

    for index = #point.cash + 1, want do
        local pile = payout.PILES[index]
        local model, lift = pileModel(pile)
        local object = nil

        if model then
            local at = GetOffsetFromEntityInWorldCoords(point.table, pile.x, pile.y, top + lift)

            object = spawn(model, at, heading + pile.heading, false)
        end

        -- The pay or the table may have changed while the model loaded.
        if point.rendering ~= mine or not point.table then
            remove(object)

            return
        end

        -- A pile this build has no model for keeps its place, so the next one stays put.
        point.cash[#point.cash + 1] = object or false
    end
end

local collectAtTable

local function build(point)
    point.building = (point.building or 0) + 1

    local mine = point.building
    local def = tableDef()

    if not def then return end

    local at = point.coords
    local object = spawn(def.model, at, at.w, true)

    if point.building ~= mine or not point.active then
        remove(object)

        return
    end

    if not object then return end

    -- Settled onto whatever is under it, so a table placed a little high or low stands.
    FreezeEntityPosition(object, false)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)

    point.def = def
    point.table = object
    point.cash = {}

    local centre = GetOffsetFromEntityInWorldCoords(object, 0.0, 0.0, def.top)

    point.zone = gg.target.addBoxZone({
        name     = ("%s_payout_%s"):format(RESOURCE, tostring(point.id)),
        coords   = vector3(centre.x, centre.y, centre.z + 0.15),
        size     = vector3(def.width, def.depth, 0.6),
        rotation = at.w,
        options  = {
            {
                name        = ("%s_payout_%s"):format(RESOURCE, tostring(point.id)),
                icon        = options.icon or "fas fa-sack-dollar",
                label       = options.label or "Collect Pay",
                distance    = tonumber(options.reach) or 2.0,
                canInteract = canCollect,
                onSelect    = function() collectAtTable(point) end,
            },
        },
    })

    render(point)
end

local function teardown(point)
    point.building = (point.building or 0) + 1
    point.rendering = (point.rendering or 0) + 1

    if point.zone then gg.target.removeZone(point.zone) end

    clearCash(point)
    remove(point.table)

    point.zone, point.table = nil, nil
end

--------------------------------------------------
-- MARK: Collecting at the table
--------------------------------------------------

-- The spot at the table's nearest edge the worker reaches from, and the heading that faces it.
local function markOf(point, from)
    local object = point.table
    local def = point.def
    local here = GetOffsetFromEntityGivenWorldCoords(object, from.x, from.y, from.z)
    local halfX, halfY = def.width * 0.5, def.depth * 0.5
    local heading = GetEntityHeading(object)
    local x, y, facing

    if math.abs(here.x) / halfX > math.abs(here.y) / halfY then
        local side = here.x >= 0 and 1 or -1

        x = side * (halfX + STAND_OFF)
        y = math.max(-halfY + 0.2, math.min(halfY - 0.2, here.y))
        facing = heading + 90.0 * side
    else
        local side = here.y >= 0 and 1 or -1

        x = math.max(-halfX + 0.2, math.min(halfX - 0.2, here.x))
        y = side * (halfY + STAND_OFF)
        facing = side > 0 and heading + 180.0 or heading
    end

    return GetOffsetFromEntityInWorldCoords(object, x, y, 0.0), facing % 360.0
end

-- The worker steps up to the table's nearest edge, takes the pay in one grab and pockets it.
collectAtTable = function(point)
    if not canCollect() or not point.table then return end

    state.busy = true

    local ped = PlayerPedId()
    local mark, heading = markOf(point, GetEntityCoords(ped))

    SetCurrentPedWeapon(ped, joaat("WEAPON_UNARMED"), true)

    if #(GetEntityCoords(ped).xy - mark.xy) > 0.25 then
        TaskGoStraightToCoord(ped, mark.x, mark.y, mark.z, 1.0, 2500, heading, 0.1)

        local deadline = GetGameTimer() + 2500

        while GetGameTimer() < deadline and #(GetEntityCoords(ped).xy - mark.xy) > 0.2 do Wait(50) end
    end

    TaskAchieveHeading(ped, heading, 500)
    Wait(500)

    -- Held as it is: the server's new total (nothing owed) can arrive before its answer, and
    -- the pay leaves the table with the hand, not before.
    point.frozen = true

    local result = gg.callback.await(("%s:payout:collect"):format(RESOURCE), point.id)

    if type(result) ~= "table" or not result.ok then
        point.frozen = false
        state.busy = false
        ClearPedTasks(ped)
        render(point)
        refuse(type(result) == "table" and result.error or "failed")

        return
    end

    local grab = grabClip()
    local take = grab and grab.take or 0.3
    local stash = grab and grab.stash or 0.8
    local length = grab and grab.length or 1.0

    if grab then TaskPlayAnim(ped, grab.dict, grab.clip, 4.0, -4.0, -1, 0, 0, false, false, false) end

    Wait(math.floor(take * 1000))

    clearCash(point)

    local held = holdInHand(ped, payout.PARTS.bundle, HAND_BONE, { 0.04, 0.0, -0.02 }, { -90.0, 0.0, 0.0 })

    Wait(math.floor((stash - take) * 1000))

    remove(held)

    Wait(math.floor((length - stash) * 1000))

    if grab then StopAnimTask(ped, grab.dict, grab.clip, 2.0) end

    point.frozen = false

    render(point)

    state.busy = false

    collected(result)
end

--------------------------------------------------
-- MARK: The depot ped hands it over
--------------------------------------------------

--- Collects at a depot ped: the ped hands over an envelope, or the case for a large pay.
---@param id number the pay point (the depot)
---@param ped number the depot ped (a local ped the job made)
---@param scene string|nil the scenario the ped goes back to
function payout.fromPed(id, ped, scene)
    if not canCollect() then
        if not owesSomething() then refuse("nothing_owed") end

        return
    end

    if not ped or not DoesEntityExist(ped) then return end

    state.busy = true

    local me = PlayerPedId()
    local large = state.owed.money >= caseFrom()

    TaskTurnPedToFaceEntity(me, ped, 700)
    Wait(700)

    local result = gg.callback.await(("%s:payout:collect"):format(RESOURCE), id)

    if type(result) ~= "table" or not result.ok then
        state.busy = false
        refuse(type(result) == "table" and result.error or "failed")

        return
    end

    local heading = GetEntityHeading(ped)
    local mine, theirs = GetEntityCoords(me), GetEntityCoords(ped)

    ClearPedTasksImmediately(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(mine.x - theirs.x, mine.y - theirs.y))

    local model = large and payout.PARTS.carry or payout.PARTS.envelope
    local object = holdInHand(ped, model, large and CARRY.bone or HAND_BONE,
        large and CARRY.offset or { 0.06, 0.0, -0.02 }, large and CARRY.rotation or { -90.0, 0.0, 0.0 })

    if gg.util.loadAnimDict(GIVE.dict) then
        TaskPlayAnim(ped, GIVE.dict, GIVE.giver, 4.0, -4.0, -1, 0, 0, false, false, false)
        TaskPlayAnim(me, GIVE.dict, GIVE.taker, 4.0, -4.0, -1, 0, 0, false, false, false)
    end

    Wait(math.floor(GIVE.pass * 1000))

    remove(object)

    local held = not large and holdInHand(me, payout.PARTS.envelope, HAND_BONE, { 0.06, 0.0, -0.02 }, { -90.0, 0.0, 0.0 }) or nil

    if large then carryCase(GetEntityCoords(me)) end

    Wait(math.floor((GIVE.length - GIVE.pass) * 1000))

    remove(held)

    if DoesEntityExist(ped) then
        SetEntityHeading(ped, heading)

        if scene and scene ~= "" then TaskStartScenarioInPlace(ped, scene, 0, true) end
    end

    state.busy = false

    collected(result)
end

--------------------------------------------------
-- MARK: API
--------------------------------------------------

--- Sets the job's pay table up. Call once.
---@param opts table
---   label      string     the target label (in the server's language)
---   icon       string     the target icon (default "fas fa-sack-dollar")
---   reach      number     target distance (default 2.0)
---   caseFrom   number|function  the pay from which the depot ped hands over the briefcase
---   canCollect function() -> boolean   extra checks (not on a route, hands free)
---   collected  function(result)        after a collection: the job's notice or panel
---   refused    function(code)          not_ready, nothing_owed, too_far, busy, failed
---   changed    function(owed)          the total changed
function payout.setup(opts)
    options = type(opts) == "table" and opts or {}

    CreateThread(function()
        local owed = gg.callback.await(("%s:payout:owed"):format(RESOURCE))

        if type(owed) == "table" then payout.setOwed(owed) end
    end)
end

--- Adds or moves a pay table. `coords` is a vector4 on the ground.
function payout.table(id, coords)
    local point = points[id]

    if point then
        if point.active then teardown(point) end

        point.active = false
        point.coords = coords

        return
    end

    points[id] = { id = id, coords = coords, active = false, cash = {} }
end

--- Takes a pay table away.
function payout.removeTable(id)
    local point = points[id]
    if not point then return end

    point.active = false
    teardown(point)
    points[id] = nil
end

--- Takes every pay table away (a job rebuilding its depots).
function payout.clearTables()
    for id in pairs(points) do payout.removeTable(id) end
end

--- Collects at a pay table, as its target does, when the worker is within reach of it.
--- Returns whether the collection started.
function payout.collect(id)
    local point = points[id]

    if not point or not point.table or not canCollect() then return false end

    local reach = (tonumber(options.reach) or 2.0) + math.max(point.def.width, point.def.depth) * 0.5

    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(point.table)) > reach then return false end

    CreateThread(function() collectAtTable(point) end)

    return true
end

--- What the worker is owed: { money, experience, count }.
function payout.owed()
    return state.owed
end

--- Whether a collection is playing or the case is still in hand.
function payout.busy()
    return state.busy or state.carrying ~= nil
end

function payout.setOwed(owed)
    state.owed = {
        money      = math.max(0, math.floor(tonumber(owed and owed.money) or 0)),
        experience = math.max(0, math.floor(tonumber(owed and owed.experience) or 0)),
        count      = math.max(0, math.floor(tonumber(owed and owed.count) or 0)),
    }

    for _, point in pairs(points) do
        if point.active and point.table then CreateThread(function() render(point) end) end
    end

    if type(options.changed) == "function" then pcall(options.changed, state.owed) end
end

RegisterNetEvent(("%s:payout:owed"):format(RESOURCE), function(owed)
    payout.setOwed(owed)
end)

-- One loop for every table: build it as the worker comes near, take it down as they go.
CreateThread(function()
    while true do
        local here = GetEntityCoords(PlayerPedId())
        local any = false

        for _, point in pairs(points) do
            any = true

            local distance = #(here - point.coords.xyz)

            if not point.active and distance < RENDER_IN then
                point.active = true
                CreateThread(function() build(point) end)
            elseif point.active and distance > RENDER_OUT and not state.busy then
                point.active = false
                teardown(point)
            end
        end

        Wait(any and 750 or 2000)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= RESOURCE then return end

    stow()

    for _, point in pairs(points) do teardown(point) end
end)

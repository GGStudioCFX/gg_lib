gg.payout = gg.payout or {}

-- MARK: Pay that waits at the depot
--
-- gg.payout is the pay table every GG job can share. A finished job does not drop money
-- into the worker's pocket: it waits at the depot, and the worker collects it in person.
-- Each depot picks how:
--   table    the pay waits on a small table, one pile of cash for every finished job not
--            yet collected. The worker clicks it and takes it in one grab.
--   ped      the depot ped hands it over: an envelope, or the case when it is a lot.
--   instant  paid the moment the job ends, as before.
--
-- The ledger is one row per worker and job in gg_studio_job_payouts, so a job resource
-- that restarts, or a worker who logs off, keeps what is owed. modules/payout/README.md
-- is the full contract.

local payout = gg.payout

payout.MODES = { "table", "ped", "instant" }

payout.MODE_SET = { table = true, ped = true, instant = true }

-- The table, newest first: a model missing from the game build falls back to the next one.
-- `top` is the height of the table top above its origin, measured from the archetype;
-- `width` (x) and `depth` (y) are its footprint.
payout.TABLES = {
    -- A small square folding table, every build.
    { model = "prop_rub_table_01", top = 0.3824, width = 1.056, depth = 1.02 },
}

-- The piles, in the order they are set out: one for every finished job, up to all of them.
-- x, y and heading are local to the table (x along it, y across it, the front at -y);
-- `lift` raises a model whose origin is not at its base onto the top. A model missing from
-- the build shows its `fallback` instead (a base game pile, lifted its own way).
payout.PILES = {
    { model = "prop_cash_case_01",       x = 0.00,  y = 0.20,  heading = 183.0, lift = 0.045 },
    { model = "h4_prop_h4_cash_bag_01a", x = 0.36,  y = 0.22,  heading = 17.7,  lift = 0.040, fallback = { model = "prop_cash_pile_01", lift = 0.046 } },
    { model = "ex_cash_roll_01",         x = -0.36, y = 0.22,  heading = 263.0, lift = 0.011, fallback = { model = "prop_cash_pile_01", lift = 0.046 } },
    { model = "prop_poly_bag_money",     x = 0.25,  y = -0.24, heading = 67.3,  lift = 0.006 },
    { model = "prop_poly_bag_money",     x = -0.25, y = -0.26, heading = -76.7, lift = 0.006 },
}

payout.PARTS = {
    bundle   = "bkr_prop_money_wrapped_01", -- what the hand closes on as it takes the pay
    carry    = "prop_ld_case_01",           -- the closed briefcase the depot ped hands over
    envelope = "prop_cash_envelope_01",     -- what the depot ped hands over for a small pay
}

--- How many piles a pay shows: one for every finished job, and one for pay with no job
--- count (experience alone, or a pay added by hand).
---@param owed table { money, experience, count }
function payout.piles(owed)
    if type(owed) ~= "table" then return 0 end

    local count = math.max(0, math.floor(tonumber(owed.count) or 0))
    local any = count > 0 or (tonumber(owed.money) or 0) > 0 or (tonumber(owed.experience) or 0) > 0

    if not any then return 0 end

    return math.max(1, math.min(#payout.PILES, count))
end

--- The parts for a settings `preview_object.with`: every pile as it sits on the table, so
--- placing a table in /ggsettings shows the whole set.
function payout.previewParts(tableIndex)
    local tableDef = payout.TABLES[tableIndex or 1]
    local parts = {}

    for _, pile in ipairs(payout.PILES) do
        parts[#parts + 1] = { model = pile.model, offset = { pile.x, pile.y, tableDef.top + pile.lift } }
    end

    return parts
end

--- A pay mode an owner picked, or the fallback.
function payout.mode(value, fallback)
    if payout.MODE_SET[value] then return value end

    return payout.MODE_SET[fallback] and fallback or "table"
end

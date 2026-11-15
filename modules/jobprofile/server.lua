gg.jobprofile = gg.jobprofile or {}

-- MARK: One profile for every GG job
--
-- Every GG job tablet (the jobs kit) opens the same Profile page. Each job reports
-- its own row here when a worker's progress changes: its name and icon, the level and
-- the XP into it, two headline stats and its badges, in the server's language. A
-- profile is then one read of every job's row, so a job whose resource is stopped
-- still shows. The banner belongs to the player and is the same on every tablet.
--
-- Rows are JSON, so a job can report what it has without a table change here.

-- The banners every tablet can draw (the jobs kit's kit/profile/banners.ts): Los Santos
-- districts on Rockstar's map tiles. Lore-friendly and free; nothing is uploaded.
gg.jobprofile.BANNERS = {
    "davis", "vinewood", "downtown", "del_perro", "port", "lsia", "mirror_park", "sandy", "paleto",
}

local banners = {}

for _, id in ipairs(gg.jobprofile.BANNERS) do banners[id] = true end

local ready = false

local function prepare()
    if ready then return true end

    local ok, err = pcall(function()
        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_profiles` (
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `banner` VARCHAR(32) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`) USING BTREE
        )
        COLLATE='utf8mb4_general_ci'
        ENGINE=InnoDB;
        ]=])

        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_progress` (
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `data` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `job`) USING BTREE
        )
        COLLATE='utf8mb4_general_ci'
        ENGINE=InnoDB;
        ]=])
    end)

    if not ok then
        gg.print.error(("Job profiles unavailable: %s"):format(err))

        return false
    end

    ready = true

    return true
end

local function valid(identifier)
    return type(identifier) == "string" and identifier ~= "" and #identifier <= 64
end

-- The last row written per identifier and job, so an unchanged save writes nothing.
local written = {}

--- Files a job's row for one worker. `data` is a table the tablets read as is:
--- label, icon (Font Awesome class), level, max_level, xp, xp_from, xp_to (nil at the top),
--- stats = { { label, value, icon, money } } (two at most), badges = earned, badge_total.
function gg.jobprofile.report(identifier, job, data)
    if not valid(identifier) or type(job) ~= "string" or job == "" or type(data) ~= "table" then return false end
    if not prepare() then return false end

    local encoded = json.encode(data)
    local key = identifier .. "\0" .. job

    if written[key] == encoded then return true end

    written[key] = encoded

    MySQL.insert.await(
        "INSERT INTO gg_studio_job_progress (identifier, job, data) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)",
        { identifier, job, encoded }
    )

    return true
end

--- Everything one profile shows: { banner = id|nil, jobs = { [job] = data } }.
function gg.jobprofile.get(identifier)
    if not valid(identifier) or not prepare() then return { banner = nil, jobs = {} } end

    local banner = MySQL.scalar.await("SELECT banner FROM gg_studio_job_profiles WHERE identifier = ?", { identifier })
    local rows = MySQL.query.await("SELECT job, data, UNIX_TIMESTAMP(updated_at) AS at FROM gg_studio_job_progress WHERE identifier = ?", { identifier }) or {}
    local jobs = {}

    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.data or "")

        if ok and type(data) == "table" then
            data.at = math.floor(tonumber(row.at) or 0)
            jobs[row.job] = data
        end
    end

    return { banner = banners[banner] and banner or nil, jobs = jobs }
end

--- Sets the player's banner (one of gg.jobprofile.BANNERS). Returns true when it is set.
function gg.jobprofile.setBanner(identifier, banner)
    if not valid(identifier) or not banners[banner] or not prepare() then return false end

    MySQL.insert.await(
        "INSERT INTO gg_studio_job_profiles (identifier, banner) VALUES (?, ?) ON DUPLICATE KEY UPDATE banner = VALUES(banner)",
        { identifier, banner }
    )

    return true
end

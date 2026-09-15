
settings = settings or {}
settings.store = settings.store or {}

local RESOURCE = GetCurrentResourceName()

local overrides = {}   -- path -> stored value
local orphaned  = {}   -- path -> stored value for paths no longer in the schema
local revision  = 0
local ready     = false

local function ensureTables()
    MySQL.query.await([=[
    CREATE TABLE IF NOT EXISTS `gg_studio_settings` (
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `path` VARCHAR(190) NOT NULL COLLATE 'utf8mb4_general_ci',
        `value` TEXT NOT NULL,
        `updated_by` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`resource`, `path`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=])

    MySQL.query.await([=[
    CREATE TABLE IF NOT EXISTS `gg_studio_settings_meta` (
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `revision` BIGINT NOT NULL DEFAULT 0,
        `version` VARCHAR(32) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        PRIMARY KEY (`resource`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=])

    gg.db.migrate("settings_meta_version_column", function()
        local rows = MySQL.query.await([[
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gg_studio_settings_meta' AND COLUMN_NAME = 'version'
        ]])

        if rows and #rows > 0 then return end

        MySQL.query.await("ALTER TABLE `gg_studio_settings_meta` ADD COLUMN `version` VARCHAR(32) NULL DEFAULT NULL")
    end)

    -- TEXT holds 64 KB; a long list of zones or a roster grown by an import
    -- passes every check and then does not fit.
    gg.db.migrate("settings_value_mediumtext", function()
        MySQL.query.await("ALTER TABLE `gg_studio_settings` MODIFY `value` MEDIUMTEXT NOT NULL")
    end)
end

local function encode(value)
    return json.encode({ v = value })
end

local function decode(raw)
    local ok, wrapper = pcall(json.decode, raw)
    if not ok or type(wrapper) ~= "table" then return nil end

    return wrapper.v
end

local function loadOverrides()
    local rows = MySQL.query.await(
        "SELECT path, value FROM gg_studio_settings WHERE resource = ?",
        { RESOURCE }
    )

    local loaded = {}
    local undecodable = 0

    for _, row in ipairs(rows or {}) do
        local value = decode(row.value)

        if value ~= nil then
            loaded[row.path] = value
        else
            undecodable = undecodable + 1
            gg.print.error(("Settings: row '%s' could not be decoded, using the default. Raw value: %s"):format(row.path, tostring(row.value)))
        end
    end

    gg.print.debug(("Settings: read %d row(s) from the database for %s"):format(#(rows or {}), RESOURCE))

    return loaded, undecodable
end

local function applyRenames(loaded)
    for path, def in pairs(settings.schema) do
        local sources = type(def.renamed_from) == "string" and { def.renamed_from } or def.renamed_from

        if type(sources) == "table" and loaded[path] == nil then
            for _, old in ipairs(sources) do
                if loaded[old] ~= nil then
                    local ok = pcall(MySQL.query.await,
                        "UPDATE gg_studio_settings SET path = ? WHERE resource = ? AND path = ?",
                        { path, RESOURCE, old })

                    if ok then
                        loaded[path] = loaded[old]
                        loaded[old] = nil
                        gg.print.debug(("Settings: migrated stored override '%s' -> '%s'"):format(old, path))
                    end

                    break
                end
            end
        end
    end
end

local function partitionOrphans(loaded)
    local active = {}
    local names = {}

    for path, value in pairs(loaded) do
        if settings.schema[path] then
            active[path] = value
        else
            orphaned[path] = value
            names[#names + 1] = path
        end
    end

    if #names > 0 then
        table.sort(names)
        gg.print.debug(("Settings: %d stored override(s) no longer match a declared setting (kept; prune via gg_settings_prune): %s")
            :format(#names, table.concat(names, ", ")))
    end

    return active
end

local function syncStoredVersion()
    local current = GetResourceMetadata(RESOURCE, "version", 0) or "0.0.0"

    local rows = MySQL.query.await(
        "SELECT version FROM gg_studio_settings_meta WHERE resource = ?",
        { RESOURCE }
    )

    local stored = rows and rows[1] and rows[1].version or nil

    if stored ~= current then
        if stored then
            gg.print.debug(("Settings: stored config last written by v%s, now running v%s"):format(stored, current))
        end

        MySQL.query.await(
            "UPDATE gg_studio_settings_meta SET version = ? WHERE resource = ?",
            { current, RESOURCE }
        )
    end
end

local function loadRevision()
    local rows = MySQL.query.await(
        "SELECT revision FROM gg_studio_settings_meta WHERE resource = ?",
        { RESOURCE }
    )

    if rows and rows[1] then
        return tonumber(rows[1].revision) or 0
    end

    MySQL.insert.await(
        "INSERT INTO gg_studio_settings_meta (resource, revision) VALUES (?, 0)",
        { RESOURCE }
    )

    return 0
end

local function bumpRevision()
    revision = revision + 1

    MySQL.query.await(
        "UPDATE gg_studio_settings_meta SET revision = ? WHERE resource = ?",
        { revision, RESOURCE }
    )

    return revision
end

local HIDDEN = "<server only>"

local function loggable(path, value)
    if settings.isSecret(path) then return HIDDEN end

    return value
end

local function broadcast(changed)
    local payload = {}

    for index = 1, #changed do
        local path = changed[index]

        if not settings.isSecret(path) then
            payload[path] = settings.read(path)
        end
    end

    TriggerClientEvent(("gg_settings:%s:sync"):format(RESOURCE), -1, {
        resource = RESOURCE,
        revision = revision,
        values   = payload,
    })
end

function settings.store.snapshot()
    local values = {}

    for path in pairs(overrides) do
        if settings.schema[path] and not settings.isSecret(path) then
            values[path] = settings.read(path)
        end
    end

    return {
        resource = RESOURCE,
        revision = revision,
        values   = values,
    }
end

function settings.store.revision()
    return revision
end

function settings.store.isReady()
    return ready
end

local MAX_VALUE = 1024 * 1024

-- A path a setting used to have, as declared by the one that replaced it.
local function currentPathOf(old)
    for path, def in pairs(settings.schema) do
        local sources = type(def.renamed_from) == "string" and { def.renamed_from } or def.renamed_from

        for _, source in ipairs(type(sources) == "table" and sources or {}) do
            if source == old then return path end
        end
    end

    return nil
end

local function validateAll(changes)
    local accepted = {}
    local errors   = {}
    local renamed  = {}
    local count    = 0

    for given, value in pairs(changes) do
        local path = given
        local def  = settings.schema[path]

        if not def then
            local moved = currentPathOf(given)

            if moved and changes[moved] == nil then
                path, def = moved, settings.schema[moved]
                renamed[given] = moved
            end
        end

        if not def then
            errors[given] = "is not a known setting"
        else
            local ok, result = true, value

            if type(def.migrate) == "function" then
                ok, result = pcall(def.migrate, settings.deepCopy(value))
                if not ok then result = "could not be read from an older version" end
            end

            if ok then ok, result = settings.validate(def, result) end

            if ok and #encode(result) > MAX_VALUE then
                ok, result = false, "is too large to store"
            end

            if ok then
                accepted[path] = result
                count = count + 1
            else
                errors[given] = result
            end
        end
    end

    return accepted, errors, count, renamed
end

-- The same verdict a save would reach, without the save. Every value that
-- passed comes back the way it would be stored and shown afterwards,
-- shipped rows included, so what is put on the page is what a save would
-- leave there.
function settings.store.check(changes)
    if type(changes) ~= "table" then return { ok = false, errors = { _ = "malformed payload" } } end
    if not ready then return { ok = false, errors = { _ = "settings are still loading" } } end

    local accepted, errors, _, renamed = validateAll(changes)

    for path, value in pairs(accepted) do
        local def = settings.schema[path]

        if def.merge_key then accepted[path] = settings.mergeKeyedDefaults(def, settings.deepCopy(value)) end
    end

    return { ok = next(errors) == nil, errors = errors, accepted = accepted, renamed = renamed, revision = revision }
end

function settings.store.save(changes, actor, expectedRevision)
    if type(changes) ~= "table" then return false, { _ = "malformed payload" } end
    if not ready then return false, { _ = "settings are still loading" } end

    if expectedRevision ~= nil and tonumber(expectedRevision) ~= revision then
        return false, { _ = "settings changed since this page was opened -- refresh and try again" }
    end

    local accepted, errors, count = validateAll(changes)

    if next(errors) then return false, errors end
    if count == 0 then return true, {} end

    local queries = {}

    for path, value in pairs(accepted) do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO gg_studio_settings (resource, path, value, updated_by)
                VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE value = VALUES(value), updated_by = VALUES(updated_by)
            ]],
            values = { RESOURCE, path, encode(value), actor },
        }
    end

    local ok, result = pcall(function()
        return MySQL.transaction.await(queries)
    end)

    if not ok then
        gg.print.error(("Failed to persist settings: %s"):format(result))
        return false, { _ = "database write failed" }
    end

    if result == false then
        gg.print.error("Settings: the database rolled the write back; nothing was saved")
        return false, { _ = "database write failed" }
    end

    local written = {}
    for path in pairs(accepted) do written[#written + 1] = path end

    local placeholders = string.rep("?", #written, ",")
    local check = { RESOURCE }
    for index = 1, #written do check[#check + 1] = written[index] end

    local verifyOk, rows = pcall(MySQL.query.await,
        ("SELECT path FROM gg_studio_settings WHERE resource = ? AND path IN (%s)"):format(placeholders),
        check)

    if verifyOk then
        local found = {}
        for _, row in ipairs(rows or {}) do found[row.path] = true end

        local missing = {}
        for index = 1, #written do
            if not found[written[index]] then missing[#missing + 1] = written[index] end
        end

        if #missing > 0 then
            gg.print.error(("Settings: the database accepted the write but %d row(s) are not there: %s")
                :format(#missing, table.concat(missing, ", ")))
        else
            gg.print.debug(("Settings: %s stored %d override(s)"):format(actor or "someone", #written))
        end
    end

    local history = {}
    for path, value in pairs(accepted) do
        history[#history + 1] = { path = path, action = "change", old = loggable(path, overrides[path]), new = loggable(path, value) }
    end

    pcall(function()
        exports.gg_lib:ggLogChange(history, actor)
    end)

    for path, value in pairs(accepted) do
        overrides[path] = value
    end

    local changed = settings.applyLive(accepted)
    bumpRevision()
    broadcast(changed)

    return true, changed
end

function settings.store.reset(paths, actor, expectedRevision)
    if type(paths) ~= "table" then return false, { _ = "malformed payload" } end
    if not ready then return false, { _ = "settings are still loading" } end

    if expectedRevision ~= nil and tonumber(expectedRevision) ~= revision then
        return false, { _ = "settings changed since this page was opened -- refresh and try again" }
    end

    local targets = {}
    local restore = {}

    for _, path in ipairs(paths) do
        local def = settings.schema[path]

        if def then
            targets[#targets + 1] = path
            restore[path] = settings.deepCopy(def.default)
        end
    end

    if #targets == 0 then return true, {} end

    local placeholders = string.rep("?", #targets, ",")
    local values = { RESOURCE }

    for index = 1, #targets do
        values[#values + 1] = targets[index]
    end

    local ok, err = pcall(function()
        MySQL.query.await(
            ("DELETE FROM gg_studio_settings WHERE resource = ? AND path IN (%s)"):format(placeholders),
            values
        )
    end)

    if not ok then
        gg.print.error(("Failed to reset settings: %s"):format(err))
        return false, { _ = "database write failed" }
    end

    local history = {}
    for index = 1, #targets do
        local path = targets[index]
        history[#history + 1] = { path = path, action = "reset", old = loggable(path, overrides[path]), new = loggable(path, restore[path]) }
    end

    pcall(function()
        exports.gg_lib:ggLogChange(history, actor)
    end)

    for index = 1, #targets do
        overrides[targets[index]] = nil
    end

    local changed = settings.applyLive(restore)
    bumpRevision()
    broadcast(changed)

    if actor then
        gg.print.debug(("%s reset %d setting(s)"):format(actor, #targets))
    end

    return true, changed
end

function settings.store.orphans()
    local names = {}
    for path in pairs(orphaned) do names[#names + 1] = path end
    table.sort(names)

    return names
end

function settings.store.prune(actor)
    local targets = settings.store.orphans()
    if #targets == 0 then return true, {} end

    local placeholders = string.rep("?", #targets, ",")
    local values = { RESOURCE }

    for index = 1, #targets do
        values[#values + 1] = targets[index]
    end

    local ok, err = pcall(function()
        MySQL.query.await(
            ("DELETE FROM gg_studio_settings WHERE resource = ? AND path IN (%s)"):format(placeholders),
            values
        )
    end)

    if not ok then
        gg.print.error(("Failed to prune settings: %s"):format(err))
        return false, { _ = "database write failed" }
    end

    orphaned = {}
    gg.print.log(("%s pruned %d orphaned setting override(s)"):format(actor or "console", #targets))

    return true, targets
end

CreateThread(function()
    ensureTables()

    revision = loadRevision()
    syncStoredVersion()

    local loaded = loadOverrides()
    applyRenames(loaded)
    overrides = partitionOrphans(loaded)

    local declared = 0
    for _ in pairs(settings.schema) do declared = declared + 1 end

    if declared == 0 then
        gg.print.error("Settings: no settings were declared before the store loaded -- every stored value will be ignored")
    end

    settings.resolve(overrides)

    ready = true

    TriggerEvent("gg_settings:ready")
end)

exports("ggSettingsPing", function()
    return true
end)

exports("ggSettingsDescribe", function()
    if not settings.store.isReady() then return nil end

    local payload = settings.describe()
    payload.revision = settings.store.revision()

    return payload
end)

exports("ggSettingsApply", function(changes, actor, expectedRevision)
    local ok, result = settings.store.save(changes, actor, expectedRevision)

    return { ok = ok, result = result, revision = settings.store.revision() }
end)

exports("ggSettingsCheck", function(changes)
    return settings.store.check(changes)
end)

exports("ggSettingsReset", function(paths, actor, expectedRevision)
    local ok, result = settings.store.reset(paths, actor, expectedRevision)

    return { ok = ok, result = result, revision = settings.store.revision() }
end)

exports("ggSettingsPrune", function(actor)
    local ok, result = settings.store.prune(actor)

    return { ok = ok, result = result }
end)

GGCallback.register(("gg_settings:%s:snapshot"):format(RESOURCE), function()
    if not settings.store.isReady() then return false end

    return true, settings.store.snapshot()
end)

exports("ggGenericSync", function(payload)
    settings.generic.apply(payload)
end)

local function fetchGeneric()
    local ok, payload = pcall(function()
        return exports.gg_lib:ggGenericFetch()
    end)

    if not ok or type(payload) ~= "table" then return false end

    settings.generic.apply(payload)

    return true
end

CreateThread(function()
    for _ = 1, 50 do
        if GetResourceState("gg_lib") == "started" and fetchGeneric() then return end
        Wait(1000)
    end

    gg.print.warn("Could not fetch generic settings from gg_lib; cfg.generic is empty")
end)

AddEventHandler("onResourceStart", function(resource)
    if resource ~= "gg_lib" then return end

    SetTimeout(1000, fetchGeneric)
end)

CreateThread(function()
    Wait(0)

    local alias = settings.info.command
    if not alias then return end

    RegisterCommand(alias, function(source)
        exports.gg_lib:ggOpenSettings(source, RESOURCE)
    end, false)
end)

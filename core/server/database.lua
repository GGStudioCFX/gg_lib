
Database = {}

local ready = false

local TABLES = {
    [=[
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
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_settings_meta` (
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `revision` BIGINT NOT NULL DEFAULT 0,
        `version` VARCHAR(32) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        PRIMARY KEY (`resource`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_log` (
        `id` BIGINT NOT NULL AUTO_INCREMENT,
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `path` VARCHAR(190) NOT NULL COLLATE 'utf8mb4_general_ci',
        `action` VARCHAR(16) NOT NULL DEFAULT 'change' COLLATE 'utf8mb4_general_ci',
        `old_value` TEXT NULL,
        `new_value` TEXT NULL,
        `actor` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `changed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`) USING BTREE,
        INDEX `idx_changed_at` (`changed_at`) USING BTREE,
        INDEX `idx_resource` (`resource`, `changed_at`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_roles` (
        `id` VARCHAR(48) NOT NULL COLLATE 'utf8mb4_general_ci',
        `label` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `icon` VARCHAR(48) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `permissions` TEXT NOT NULL,
        `created_by` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_admins` (
        `identifier` VARCHAR(96) NOT NULL COLLATE 'utf8mb4_general_ci',
        `name` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `granted_by` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `granted_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],
    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_admin_seen` (
        `identifier` VARCHAR(96) NOT NULL COLLATE 'utf8mb4_general_ci',
        `name` VARCHAR(100) DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `last_open` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `opens` INT NOT NULL DEFAULT 1,
        PRIMARY KEY (`identifier`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_migrations` (
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `key` VARCHAR(190) NOT NULL COLLATE 'utf8mb4_general_ci',
        `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`resource`, `key`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_action_routes` (
        `id` BIGINT NOT NULL AUTO_INCREMENT,
        `action` VARCHAR(160) NOT NULL COLLATE 'utf8mb4_general_ci',
        `kind` VARCHAR(16) NOT NULL COLLATE 'utf8mb4_general_ci',
        `label` VARCHAR(64) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `target` TEXT NULL,
        `message` TEXT NULL,
        `enabled` TINYINT NOT NULL DEFAULT 1,
        `created_by` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`) USING BTREE,
        INDEX `action` (`action`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],

    [=[
    CREATE TABLE IF NOT EXISTS `gg_studio_action_log` (
        `id` BIGINT NOT NULL AUTO_INCREMENT,
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `action` VARCHAR(96) NOT NULL COLLATE 'utf8mb4_general_ci',
        `source` INT NULL DEFAULT NULL,
        `identifier` VARCHAR(96) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `player` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `character_name` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
        `data` TEXT NULL,
        `fired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`) USING BTREE,
        INDEX `resource_action` (`resource`, `action`) USING BTREE,
        INDEX `identifier` (`identifier`) USING BTREE,
        INDEX `fired_at` (`fired_at`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=],
}

local function migrate(key, statement)
    local resource = GetCurrentResourceName()

    local rows = MySQL.query.await("SELECT 1 FROM gg_studio_migrations WHERE resource = ? AND `key` = ? LIMIT 1", { resource, key })

    if rows and rows[1] then return false end

    local ok, err = pcall(statement)

    if not ok then
        print(("^1[gg_lib]^7 migration '%s' failed: %s"):format(key, tostring(err)))

        return false
    end

    MySQL.insert.await("INSERT IGNORE INTO gg_studio_migrations (resource, `key`) VALUES (?, ?)", { resource, key })

    return true
end

local function addColumn(table_, column, definition)
    local ok = pcall(MySQL.query.await,
        ("ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `%s` %s"):format(table_, column, definition))

    if not ok then
        pcall(MySQL.query.await,
            ("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(table_, column, definition))
    end
end

function Database.isReady()
    return ready
end

CreateThread(function()
    for index = 1, #TABLES do
        MySQL.query.await(TABLES[index])
    end

    addColumn("gg_studio_settings_meta", "version", "VARCHAR(32) NULL DEFAULT NULL")

    addColumn("gg_studio_admins", "role", "VARCHAR(48) NOT NULL DEFAULT 'admin'")

    addColumn("gg_studio_action_routes", "message", "TEXT NULL")

    addColumn("gg_studio_action_log", "character_name", "VARCHAR(100) NULL DEFAULT NULL")

    migrate("drop_minigame_settings", function()
        MySQL.query.await("DELETE FROM gg_studio_settings WHERE resource = ? AND path LIKE ?", { "gg_studio", "minigames.%" })
    end)

    ready = true
    TriggerEvent("gg_lib:database:ready")
end)

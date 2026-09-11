
Admins = {}

local CONFIG_FILE = "server_config.lua"

local ACE_EDIT = "gg.settings"
local ACE_VIEW = "gg.settings.view"

local KNOWN_TYPES = {
    license2 = true, license = true, steam = true,
    discord  = true, fivem   = true, xbl   = true,
    live     = true, ip      = true,
}

local DEFAULT_TYPE = "license2"

local config       = { ace = true }
local fromConfig   = {}   -- "type:value" -> entry as written
local fromDatabase = {}

local function normalize(entry)
    if type(entry) ~= "string" then return nil, "is not a string" end

    local value = entry:gsub("%s", ""):lower()
    if value == "" then return nil end

    local kind, rest = value:match("^([%a%d]+):(.+)$")

    if not kind then
        return ("%s:%s"):format(DEFAULT_TYPE, value)
    end

    if not KNOWN_TYPES[kind] then
        return nil, ("'%s:' is not a known identifier type"):format(kind)
    end

    return ("%s:%s"):format(kind, rest)
end

local function loadConfig()
    local source = LoadResourceFile("gg_lib", CONFIG_FILE)

    if not source or source == "" then
        print(("^3[gg_lib] %s is missing -- put it back and add your license2 to the admins list^0"):format(CONFIG_FILE))
        return false
    end

    local chunk, compileError = load(source, ("@@gg_lib/%s"):format(CONFIG_FILE), "t")

    if not chunk then
        print(("^1[gg_lib] %s has a syntax error: %s^0"):format(CONFIG_FILE, compileError))
        return false
    end

    local ok, result = pcall(chunk)

    if not ok or type(result) ~= "table" then
        print(("^1[gg_lib] %s did not return a table^0"):format(CONFIG_FILE))
        return false
    end

    local loaded = {}
    local count  = 0

    for _, entry in ipairs(result.admins or {}) do
        local key, problem = normalize(entry)

        if key then
            if not loaded[key] then count = count + 1 end
            loaded[key] = entry
        elseif problem then
            print(("^3[gg_lib] ignoring admin '%s' -- %s^0"):format(tostring(entry), problem))
        end
    end

    config     = result
    fromConfig = loaded

    return true, count
end

function Admins.normalize(entry)
    return normalize(entry)
end

function Admins.setting(key)
    return config and config[key] or nil
end

function Admins.isConsole(source)
    return source == 0 or source == "0"
end

function Admins.license2(source)
    return GetPlayerIdentifierByType(source, "license2")
end

function Admins.actor(source)
    if Admins.isConsole(source) then return "console" end

    local identifier = (GGName and GGName.identifier and GGName.identifier(source))
        or Admins.license2(source)
        or GetPlayerIdentifierByType(source, "license")
        or GetPlayerIdentifierByType(source, "steam")

    local who = GGName and GGName.both and GGName.both(source) or GetPlayerName(source) or "unknown"

    return ("%s (%s)"):format(who, identifier or source)
end

function Admins.isAdmin(source)
    if Admins.isConsole(source) then return true end

    local player = tonumber(source)
    if not player then return false end

    for _, identifier in ipairs(GetPlayerIdentifiers(player) or {}) do
        local key = identifier:lower()

        if fromConfig[key] or fromDatabase[key] then return true end
    end

    return Admins.roleOf(source) ~= nil
end

function Admins.isConfigAdmin(identifier)
    return fromConfig[identifier] ~= nil
end

local ACE_ROLES = {
    ["group.god"]        = "admin",
    ["group.superadmin"] = "admin",
    ["group.admin"]      = "admin",
    ["qbcore.god"]       = "admin",
    ["qbcore.admin"]     = "admin",
    ["qbx.god"]          = "admin",
    ["qbx.admin"]        = "admin",
    ["group.mod"]        = "moderator",
    ["group.moderator"]  = "moderator",
}

local FRAMEWORK_GROUPS = {
    superadmin = "admin",
    god        = "admin",
    admin      = "admin",
    mod        = "moderator",
    moderator  = "moderator",
}

local function running(name)
    local state = GetResourceState(name)

    return state == "started" or state == "starting"
end

local function frameworkGroup(source)
    if running("es_extended") then
        local ok, group = pcall(function()
            local core = exports.es_extended:getSharedObject()
            local player = core and core.GetPlayerFromId(source)

            return player and player.getGroup and player.getGroup()
        end)

        if ok and type(group) == "string" then return group:lower() end
    end

    if running("qb-core") then
        local ok, group = pcall(function()
            local core = exports["qb-core"]:GetCoreObject()
            if not (core and core.Functions and core.Functions.GetPermission) then return nil end

            local held = core.Functions.GetPermission(source)

            if type(held) == "string" then return held end

            if type(held) == "table" then
                for name, allowed in pairs(held) do
                    if allowed and FRAMEWORK_GROUPS[tostring(name):lower()] then return name end
                end
            end

            return nil
        end)

        if ok and type(group) == "string" then return group:lower() end
    end

    return nil
end

local announced = {}

local function announce(source, role, why)
    local key = Admins.license2(source) or tostring(source)

    if announced[key] then return end

    announced[key] = true

    print(("[gg_lib] %s is %s here because of %s. Set auto_admin = false in server_config.lua to stop this."):format(
        Admins.actor(source), role, why))
end

AddEventHandler("playerDropped", function()
    local key = Admins.license2(source)

    if key then announced[key] = nil end
end)

function Admins.serverRole(source)
    if config.auto_admin == false then return nil end
    if Admins.isConsole(source) then return nil end

    local best, why = nil, nil

    for ace, role in pairs(ACE_ROLES) do
        if IsPlayerAceAllowed(source, ace) then
            if role == "admin" then return role, ace end

            best, why = best or role, why or ace
        end
    end

    local group = frameworkGroup(source)
    local fromGroup = group and FRAMEWORK_GROUPS[group]

    if fromGroup == "admin" then return fromGroup, ("the %s group"):format(group) end

    if fromGroup and not best then return fromGroup, ("the %s group"):format(group) end

    return best, why
end

function Admins.roleOf(source)
    if Admins.isConsole(source) then return Roles.OWNER end

    local player = tonumber(source)

    if player then
        for _, identifier in ipairs(GetPlayerIdentifiers(player) or {}) do
            local key = identifier:lower()

            if fromConfig[key] then return Roles.OWNER end

            local granted = fromDatabase[key]

            if granted then
                local role = granted.role

                return (Roles.exists(role) and role) or Roles.DEFAULT
            end
        end
    end

    if config.ace ~= false then
        if IsPlayerAceAllowed(source, ACE_EDIT) then return Roles.DEFAULT end
        if IsPlayerAceAllowed(source, ACE_VIEW) then return "moderator" end
    end

    local earned, why = Admins.serverRole(source)

    if earned then
        announce(source, earned, why)

        return earned
    end

    return nil
end

function Admins.can(source, action, resource)
    local role = Admins.roleOf(source)
    if not role then return false end

    return Roles.can(role, action, resource)
end

function Admins.canEdit(source, resource)
    return Admins.can(source, "edit", resource)
end

function Admins.canView(source, resource)
    return Admins.can(source, "view", resource)
end

function Admins.canManage(source)
    return Admins.can(source, "manage_admins")
end

exports("ggIsAdmin", function(source)
    return Admins.isAdmin(source)
end)

local function loadDatabase()
    local ok, rows = pcall(MySQL.query.await, "SELECT identifier, name, role FROM gg_studio_admins")

    if not ok then return end

    local loaded = {}

    for _, row in ipairs(rows or {}) do
        local key = normalize(row.identifier)

        if key then
            loaded[key] = {
                name = row.name or row.identifier,
                role = row.role or Roles.DEFAULT,
            }
        end
    end

    fromDatabase = loaded
end

AddEventHandler("gg_lib:database:ready", loadDatabase)

function Admins.grant(identifier, name, grantedBy, role)
    role = (Roles.exists(role) and role) or Roles.DEFAULT

    if role == Roles.OWNER then role = Roles.DEFAULT end

    local ok = pcall(MySQL.query.await, [[
        INSERT INTO gg_studio_admins (identifier, name, granted_by, role)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), granted_by = VALUES(granted_by), role = VALUES(role)
    ]], { identifier, name, grantedBy, role })

    if not ok then return false end

    fromDatabase[identifier] = { name = name or identifier, role = role }

    return true
end

function Admins.setRole(identifier, role)
    local current = fromDatabase[identifier]
    if not current then return false, "that identifier is not an admin here" end
    if not Roles.exists(role) then return false, "no such role" end
    if role == Roles.OWNER then return false, "owner comes from server_config.lua" end

    local ok = pcall(MySQL.query.await,
        "UPDATE gg_studio_admins SET role = ? WHERE identifier = ?", { role, identifier })

    if not ok then return false, "the database refused the change" end

    current.role = role

    return true
end

function Admins.revoke(identifier)
    local ok = pcall(MySQL.query.await,
        "DELETE FROM gg_studio_admins WHERE identifier = ?", { identifier })

    if not ok then return false end

    fromDatabase[identifier] = nil

    return true
end

local function onlineNames()
    local names = {}

    for _, player in ipairs(GetPlayers()) do
        local identifier = normalize(Admins.license2(player) or "")
        if identifier then names[identifier] = GetPlayerName(player) end
    end

    return names
end

local function listAdmins()
    local list = {}
    local seen = {}
    local names = onlineNames()

    local live = {}

    for _, player in ipairs(GetPlayers()) do
        local face = GG_FACES.fetchFor(player)

        for index = 0, GetNumPlayerIdentifiers(player) - 1 do
            local held = normalize(GetPlayerIdentifier(player, index) or "")

            if held then live[held] = face end
        end
    end

    local function faceOf(identifier)
        local discord = GG_FACES.discordId(identifier)

        if discord then
            local found = GG_FACES.fetchDiscord(discord)

            if found then return found end
        end

        local cfx = GG_FACES.cfxId(identifier)

        if cfx then
            local found = GG_FACES.fetchCfx(cfx)

            if found then return found end
        end

        local steam = GG_FACES.steam64(identifier)

        if steam then
            local found = GG_FACES.fetchSteam(steam)

            if found then return found end
        end

        return live[identifier]
    end

    for identifier in pairs(fromConfig) do
        seen[identifier] = true
        list[#list + 1] = {
            identifier = identifier,
            name       = names[identifier],
            face       = faceOf(identifier),
            source     = "config",
            role       = Roles.OWNER,
        }
    end

    local rows = MySQL.query.await([[
        SELECT identifier, name, granted_by, role,
               DATE_FORMAT(granted_at, '%Y-%m-%d') AS granted_at
        FROM gg_studio_admins
        ORDER BY granted_at
    ]])

    for _, row in ipairs(rows or {}) do
        local identifier = normalize(row.identifier)

        if identifier and not seen[identifier] then
            list[#list + 1] = {
                identifier = identifier,
                name       = names[identifier] or row.name,
                face       = faceOf(identifier),
                source     = "database",
                role       = (Roles.exists(row.role) and row.role) or Roles.DEFAULT,
                granted_by = row.granted_by,
                granted_at = row.granted_at,
            }
        end
    end

    for _, player in ipairs(GetPlayers()) do
        local identifier = normalize(Admins.license2(player) or "")
        local earned, why = Admins.serverRole(player)

        if identifier and earned and not seen[identifier] then
            seen[identifier] = true

            list[#list + 1] = {
                identifier = identifier,
                name       = names[identifier],
                face       = faceOf(identifier),
                source     = "server",
                role       = earned,
                granted_by = why,
            }
        end
    end

    local ORDER = { config = 1, server = 2, database = 3 }

    table.sort(list, function(left, right)
        local a, b = ORDER[left.source] or 9, ORDER[right.source] or 9

        if a ~= b then return a < b end

        return (left.name or left.identifier) < (right.name or right.identifier)
    end)

    return list
end

local function listPlayers()
    local list = {}

    for _, player in ipairs(GetPlayers()) do
        local identifier = normalize(Admins.license2(player) or "")

        if identifier then
            list[#list + 1] = {
                id         = tonumber(player),
                name       = GetPlayerName(player) or "unknown",
                identifier = identifier,
                admin      = (fromConfig[identifier] or fromDatabase[identifier]) ~= nil,
            }
        end
    end

    table.sort(list, function(left, right) return left.name < right.name end)

    return list
end

GGCallback.register("gg_lib:admins:fetch", function(source)
    if not Admins.canView(source) then
        print(("^3[gg_lib] blocked admin fetch from %s^0"):format(Admins.actor(source)))
        return false
    end

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

GGCallback.register("gg_lib:admins:grant", function(source, data)
    if not Admins.canManage(source) then
        print(("^1[gg_lib] blocked admin GRANT from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to manage admins"
    end

    if type(data) ~= "table" then return false, "malformed payload" end

    local identifier, name

    if data.player then
        local player = tonumber(data.player)
        if not player or not GetPlayerName(player) then return false, "that player is no longer connected" end

        identifier = normalize(Admins.license2(player) or "")
        name       = GetPlayerName(player)

        if not identifier then return false, "that player has no license2 identifier" end
    else
        local problem
        identifier, problem = normalize(data.identifier)

        if not identifier then return false, problem or "that is not a valid identifier" end
    end

    if Admins.isConfigAdmin(identifier) then
        return false, "already an admin via server_config.lua"
    end

    if fromDatabase[identifier] then return false, "already an admin" end

    if not Admins.grant(identifier, name, Admins.actor(source), data.role) then
        return false, "database write failed"
    end

    print(("[gg_lib] %s granted admin to %s"):format(Admins.actor(source), identifier))

    if Logs then Logs.write({ { resource = "gg_lib", path = identifier, action = "admin_add", new = name or identifier } }, Admins.actor(source)) end

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

GGCallback.register("gg_lib:admins:setRole", function(source, data)
    if not Admins.canManage(source) then
        print(("^1[gg_lib] blocked role change from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to manage admins"
    end

    if type(data) ~= "table" then return false, "malformed payload" end

    local identifier = normalize(data.identifier)
    if not identifier then return false, "that is not a valid identifier" end

    if Admins.isConfigAdmin(identifier) then
        return false, "set in server_config.lua -- remove it there"
    end

    local ok, problem = Admins.setRole(identifier, data.role)
    if not ok then return false, problem end

    print(("[gg_lib] %s moved %s to %s"):format(Admins.actor(source), identifier, data.role))

    if Logs then
        Logs.write({ { resource = "gg_lib", path = identifier, action = "admin_role", new = data.role } }, Admins.actor(source))
    end

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

GGCallback.register("gg_lib:admins:saveRole", function(source, data)
    if not Admins.canManage(source) then
        print(("^1[gg_lib] blocked role save from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to manage admins"
    end

    local ok, problem = Roles.save(data, Admins.actor(source))
    if not ok then return false, problem end

    print(("[gg_lib] %s saved role %s"):format(Admins.actor(source), problem))

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

GGCallback.register("gg_lib:admins:deleteRole", function(source, data)
    if not Admins.canManage(source) then
        print(("^1[gg_lib] blocked role delete from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to manage admins"
    end

    local id = type(data) == "table" and data.id or nil

    local ok, problem = Roles.delete(id)
    if not ok then return false, problem end

    pcall(MySQL.query.await, "UPDATE gg_studio_admins SET role = ? WHERE role = ?", { Roles.DEFAULT, id })
    loadDatabase()

    print(("[gg_lib] %s deleted role %s"):format(Admins.actor(source), tostring(id)))

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

GGCallback.register("gg_lib:admins:revoke", function(source, data)
    if not Admins.canManage(source) then
        print(("^1[gg_lib] blocked admin REVOKE from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to manage admins"
    end

    if type(data) ~= "table" then return false, "malformed payload" end

    local identifier = normalize(data.identifier)
    if not identifier then return false, "that is not a valid identifier" end

    if Admins.isConfigAdmin(identifier) then
        return false, "set in server_config.lua -- remove it there"
    end

    if not fromDatabase[identifier] then return false, "not an admin" end

    local wasNamed = fromDatabase[identifier]
    wasNamed = type(wasNamed) == "table" and wasNamed.name or wasNamed

    if not Admins.revoke(identifier) then return false, "database write failed" end

    print(("[gg_lib] %s revoked admin from %s"):format(Admins.actor(source), identifier))

    if Logs then Logs.write({ { resource = "gg_lib", path = identifier, action = "admin_remove", old = wasNamed } }, Admins.actor(source)) end

    return true, { admins = listAdmins(), players = listPlayers(), roles = Roles.list() }
end)

local ok, count = loadConfig()

if ok and count == 0 then
    print(("^3[gg_lib] no admins configured -- add your license2 to %s^0"):format(CONFIG_FILE))
end

GGCallback.register("gg_lib:admins:detail", function(source, data)
    if not Admins.canView(source) then
        print(("^3[gg_lib] blocked admin detail from %s^0"):format(Admins.actor(source)))

        return false
    end

    local wanted = normalize(type(data) == "table" and data.identifier or "")

    if not wanted then return false end

    local detail = { identifier = wanted, identifiers = {}, online = false }

    for _, player in ipairs(GetPlayers()) do
        local held = {}
        local match = false

        for index = 0, GetNumPlayerIdentifiers(player) - 1 do
            local raw = GetPlayerIdentifier(player, index)

            if raw then
                held[#held + 1] = raw

                if normalize(raw) == wanted then match = true end
            end
        end

        if match then
            detail.online = true
            detail.source = tonumber(player)
            detail.name = GetPlayerName(player)
            detail.identifiers = held
            detail.ping = GetPlayerPing(player)

            break
        end
    end

    if #detail.identifiers == 0 then detail.identifiers = { wanted } end

    detail.studio = GG_PRESENCE and GG_PRESENCE.state and GG_PRESENCE.state(wanted) or nil

    local ok, err = pcall(function()
        local seen = MySQL.query.await([[
            SELECT `name`, `opens`,
                   DATE_FORMAT(`last_open`, '%Y-%m-%d %H:%i') AS last_open,
                   UNIX_TIMESTAMP(`last_open`) AS last_open_at
            FROM `gg_studio_admin_seen`
            WHERE `identifier` = ?
        ]], { wanted })

        if seen and seen[1] then
            detail.opens = seen[1].opens
            detail.last_open = seen[1].last_open
            detail.last_open_at = seen[1].last_open_at
            detail.name = detail.name or seen[1].name
        end

        local edits = MySQL.query.await([[
            SELECT `resource`, `path`, `action`,
                   DATE_FORMAT(`changed_at`, '%Y-%m-%d %H:%i') AS changed_at,
                   UNIX_TIMESTAMP(`changed_at`) AS changed_at_at
            FROM `gg_studio_log`
            WHERE `actor` LIKE ?
            ORDER BY `changed_at` DESC
            LIMIT 5
        ]], { "%" .. wanted .. "%" })

        detail.recent = edits or {}

        local total = MySQL.query.await([[
            SELECT COUNT(*) AS total FROM `gg_studio_log` WHERE `actor` LIKE ?
        ]], { "%" .. wanted .. "%" })

        detail.edits = (total and total[1] and total[1].total) or 0
    end)

    if not ok then gg.print.warn(("admin detail query failed: %s"):format(tostring(err))) end

    return true, detail
end)

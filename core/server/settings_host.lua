
local RESOURCE = GetCurrentResourceName()

local peers   = {}   -- sorted list of resources carrying the settings module
local peerSet = {}

local function canEdit(source)
    return Admins.canEdit(source)
end

local function canView(source)
    return Admins.canView(source)
end

local function actorFor(source)
    return Admins.actor(source)
end

-- Only a resource whose manifest loads gg_lib can carry the module, so the
-- rest are never asked: a missing export costs an event broadcast per call.
local function importsLib(resource)
    for _, key in ipairs({ "shared_script", "server_script" }) do
        for index = 0, GetNumResourceMetadata(resource, key) - 1 do
            local entry = GetResourceMetadata(resource, key, index)

            if entry and entry:find("@gg_lib/", 1, true) then return true end
        end
    end

    return false
end

local function carriesSettings(resource)
    if resource == RESOURCE then return false end

    local state = GetResourceState(resource)
    if state ~= "started" and state ~= "starting" then return false end

    if not importsLib(resource) then return false end

    local ok, alive = pcall(function()
        return exports[resource]:ggSettingsPing()
    end)

    return ok and alive == true
end

local function setPeer(resource, on)
    if (peerSet[resource] == true) == (on == true) then return end

    peerSet[resource] = on == true or nil

    local list = {}
    for name in pairs(peerSet) do list[#list + 1] = name end
    table.sort(list)

    peers = list
end

local function scanPeers()
    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)

        if resource then setPeer(resource, carriesSettings(resource)) end
    end
end

SettingsPeers = {}

function SettingsPeers.list()
    return peers
end

local function warningsFor(requires)
    if type(requires) ~= "table" then return nil end

    local warnings = {}

    local function miss(kind, need)
        warnings[#warnings + 1] = {
            kind     = kind,
            name     = need.name,
            why      = need.why,
            optional = need.optional,
        }
    end

    local resources = requires.resources or {}

    for index = 1, #resources do
        local need = resources[index]

        if GetResourceState(need.name) ~= "started" then miss("resource", need) end
    end

    local items = requires.items or {}

    if #items > 0 and gg.items and gg.items.ready and gg.items.ready() then
        for index = 1, #items do
            local need = items[index]

            if not gg.items.exists(need.name) then miss("item", need) end
        end
    end

    return #warnings > 0 and warnings or nil
end

-- Each script is described once and held as two parts with a stamp each:
-- the page itself (labels, options, groups), which only changes with a
-- restart or the language, and its values, which change with every save.
-- The client says which stamps it holds and is sent only what moved.
local BOOT = ("%x%04x"):format(os.time(), math.random(0, 0xffff))
local RECHECK = 600   -- seconds before a held description is rebuilt anyway

local described = {}
local starts    = {}
local legacy    = {}  -- running an older settings module without a stamp
local serial    = 0

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end

    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then return false end
    end

    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

local function languageCode()
    return Locales and Locales.code() or "en"
end

local function keyFor(resource)
    local own

    if resource == GenericSettings.resource then
        own = "g"
    elseif not legacy[resource] then
        local ok, value = pcall(function()
            return exports[resource]:ggSettingsStamp()
        end)

        if not ok then
            legacy[resource] = true
        elseif value ~= nil and value ~= false then
            own = tostring(value)
        end
    end

    if not own then return nil end

    return ("%d|%s|%d|%s"):format(starts[resource] or 0, own, GenericSettings.revision(), languageCode())
end

local VALUE_KEYS = { revision = true, setup = true, requires = true, can_edit = true, warnings = true, entries = true }

local function split(payload)
    local page, values, stored = {}, {}, {}

    for key, value in pairs(payload) do
        if not VALUE_KEYS[key] then page[key] = value end
    end

    local entries = payload.entries or {}

    for index = 1, #entries do
        local entry = entries[index]

        if entry.server_only then
            if entry.stored == true then stored[entry.path] = true end
        elseif entry.value ~= nil and not deepEqual(entry.value, entry.default) then
            values[entry.path] = entry.value
        end

        entry.value, entry.stored = nil, nil
    end

    page.entries = entries

    return page, {
        revision = payload.revision,
        setup    = payload.setup,
        values   = values,
        stored   = stored,
    }, payload.requires
end

local function stamped(held, encoded)
    if held and held.encoded == encoded then return held.stamp end

    serial = serial + 1

    return ("%s.%d"):format(BOOT, serial)
end

local function describe(resource)
    local ok, payload

    if resource == GenericSettings.resource then
        ok, payload = pcall(GenericSettings.describe)
    else
        ok, payload = pcall(function()
            return exports[resource]:ggSettingsDescribe()
        end)
    end

    if not ok or type(payload) ~= "table" then return nil end

    if Locales then payload = Locales.schema(payload) end

    return payload
end

local function entryFor(resource, force)
    local key  = keyFor(resource)
    local held = described[resource]

    if held and key and held.key == key and not force and os.time() - held.at < RECHECK then
        return held
    end

    local payload = describe(resource)
    if not payload then return nil end

    local page, state, requires = split(payload)

    local pageText  = json.encode(page)
    local stateText = json.encode(state)

    local entry = {
        key      = key,
        at       = os.time(),
        name     = page.resource or resource,
        page     = page,
        state    = state,
        requires = requires,
        page_mark  = { stamp = stamped(held and held.page_mark, pageText), encoded = pageText },
        state_mark = { stamp = stamped(held and held.state_mark, stateText), encoded = stateText },
    }

    entry.summary = {
        resource = entry.name,
        label    = page.label,
        short    = page.short,
        category = page.category,
        icon     = page.icon,
        order    = page.order,
        version  = page.version,
        generic  = page.generic,
        updates  = page.updates,
        revision = state.revision,
        setup    = state.setup,
        modified = next(state.values) ~= nil or next(state.stored) ~= nil,
        partial  = true,
        groups   = {},
        entries  = {},
    }

    described[resource] = entry

    return entry
end

local function shallow(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

-- What one script costs on the wire: nothing when the client holds both
-- parts, the values alone when it holds the page, the page when it is the
-- one being opened, and a line for the rail otherwise.
local function answerFor(source, entry, wanted, holds, force)
    local page, values = entry.page_mark.stamp, entry.state_mark.stamp
    local hasPage = not force and type(holds) == "table" and holds.page == page

    local out

    if hasPage and holds.values == values then
        out = { resource = entry.name, same = true }
    elseif hasPage then
        out = { resource = entry.name, state = entry.state }
    elseif wanted then
        out = shallow(entry.page)
        out.state = entry.state
    else
        out = shallow(entry.summary)
    end

    if not out.partial then
        out.page_stamp   = page
        out.values_stamp = values
    end

    out.can_edit = Admins.canEdit(source, entry.name)
    out.warnings = warningsFor(entry.requires)

    return out
end

local function sortScripts(rows)
    table.sort(rows, function(left, right)
        local orderLeft  = left.entry.summary.order or 100
        local orderRight = right.entry.summary.order or 100

        if orderLeft ~= orderRight then return orderLeft < orderRight end

        return (left.entry.summary.label or "") < (right.entry.summary.label or "")
    end)

    local out = {}
    for index = 1, #rows do out[index] = rows[index].answer end
    return out
end

local function scriptsFor(source, request)
    local holds = type(request.holds) == "table" and request.holds or {}
    local every = request.want == "*"
    local want  = {}

    for _, name in ipairs(type(request.want) == "table" and request.want or {}) do
        if type(name) == "string" then want[name] = true end
    end

    local names = { GenericSettings.resource }
    for index = 1, #peers do names[#names + 1] = peers[index] end

    local rows = {}

    for _, resource in ipairs(names) do
        local asked = every or want[resource] == true

        if (not request.only or asked) and Admins.canView(source, resource) then
            local wanted = asked or resource == GenericSettings.resource
            local whole  = request.force == true and asked

            -- `fresh` reads the script again but still answers by stamp;
            -- `force` also sends it whole, for a page that lost its copy.
            local entry  = entryFor(resource, (whole or request.fresh == true) and asked)

            if entry then
                rows[#rows + 1] = { entry = entry, answer = answerFor(source, entry, wanted, holds[entry.name], whole) }
            end
        end
    end

    return sortScripts(rows)
end

local function clip(value, limit)
    return type(value) == "string" and value ~= "" and value:sub(1, limit) or nil
end

-- The page's own words for the screen, in the server's language: it can open
-- before Script Studio ever has, so nothing else has sent them yet.
local function accessWords()
    local words = {}

    for key, value in pairs(Locales.strings() or {}) do
        if key:find("^access_") then words[key] = value end
    end

    return words
end

-- The one no-access screen. /ggsettings opens it for a player who may not get
-- in, and any script can open it for its own command: `info` names the script,
-- the command and where an admin adds a player. With none it is /ggsettings.
local function showNoAccess(source, info)
    source = tonumber(source)

    if not source or source <= 0 or not GetPlayerName(source) then return false end

    info = type(info) == "table" and info or {}

    local where = clip(info.where, 160)
    local icon  = clip(info.icon, 40)

    TriggerClientEvent("gg_lib:settings:access", source, {
        identifier = GetPlayerIdentifierByType(source, "license") or Admins.license2(source) or "",
        -- The file by its resource folder only: this goes to a player with no
        -- access, so never the server's own disk path.
        file       = ("%s/server_config.lua"):format(RESOURCE),
        command    = (clip(info.command, 32) or "ggsettings"):gsub("^/", ""),
        label      = clip(info.label, 48),
        icon       = icon and icon:match("^fa%-[%w%-]+$") and icon or nil,
        where      = where,
        strict     = where ~= nil and info.strict == true,
        store      = clip(info.store, 200),
        words      = accessWords(),
        theme      = GenericSettings.get("theme.primary_color"),
    })

    return true
end

local function openFor(source, focus)
    if source == 0 then
        print("[gg_lib] /ggsettings has no console UI; run it in game")
        return
    end

    if not canView(source) then
        showNoAccess(source)
        return
    end

    TriggerClientEvent("gg_lib:settings:open", source, {
        focus    = focus,
        can_edit = canEdit(source),
    })
end

RegisterCommand("ggsettings", function(source, args)
    openFor(source, args and args[1] or nil)
end, false)

exports("ggOpenSettings", function(source, focus)
    openFor(source, focus)
end)

-- exports.gg_lib:ggShowNoAccess(source, { command = "weather", label = "Weather System",
--     icon = "fa-cloud-sun", where = "/ggsettings, Weather System, Access", strict = false,
--     store = "https://ggstudio.store" }) -- every field optional; none is /ggsettings.
exports("ggShowNoAccess", function(source, info)
    return showNoAccess(source, info)
end)

GGCallback.register("gg_lib:settings:fetch", function(source, request)
    if not canView(source) then
        print(("^3[gg_lib] blocked settings fetch from %s -- not an admin^0"):format(actorFor(source)))
        return false
    end

    request = type(request) == "table" and request or {}

    local scripts = scriptsFor(source, request)

    if request.only then return true, { scripts = scripts } end

    local role = Admins.roleOf(source)
    local tools = {}

    for _, tool in ipairs(Roles.tools) do
        if Roles.can(role, tool.id) then tools[#tools + 1] = tool.id end
    end

    local answer = {
        scripts    = scripts,
        can_edit   = canEdit(source),
        can_manage = Admins.canManage(source),
        role       = role,
        role_label = (Roles.get(role) or {}).label,
        tools      = tools,
        theme    = GenericSettings.get("theme.primary_color"),
        fade     = GenericSettings.get("theme.fade_on_hover_out"),
        fade_to  = GenericSettings.get("theme.fade_opacity"),
    }

    -- The page's own words and the home feed only travel when they moved.
    if Locales then
        local lang = ("%s|%s"):format(BOOT, languageCode())

        if request.lang ~= lang then
            answer.ui_lang = Locales.strings()
            answer.lang    = lang
        end
    end

    if HomeFeed then
        local home = HomeFeed.stamp()

        if request.home ~= home then
            answer.home       = HomeFeed.current()
            answer.home_stamp = home
        end
    end

    return true, answer
end)

GGCallback.register("gg_lib:settings:save", function(source, data)
    if type(data) ~= "table" or type(data.resource) ~= "string" then
        return false, { _ = "malformed payload" }
    end

    if not Admins.canEdit(source, data.resource) then
        print(("^1[gg_lib] blocked settings WRITE to %s from %s^0"):format(data.resource, actorFor(source)))
        return false, { _ = "you do not have permission to change this script" }
    end

    local target  = data.resource
    local changes = type(data.changes) == "table" and data.changes or {}
    local resets  = type(data.resets) == "table" and data.resets or {}
    local actor   = actorFor(source)

    if target == GenericSettings.resource then
        local ok, result = GenericSettings.apply(changes, actor, data.revision)
        if not ok then return false, result end

        local changed = result

        if #resets > 0 then
            local resetOk, resetResult = GenericSettings.reset(resets, actor)
            if not resetOk then return false, resetResult end

            for index = 1, #resetResult do changed[#changed + 1] = resetResult[index] end
        end

        if #changed > 0 and GlobalState.gg_debug == true then
            print(("[gg_lib] [DEBUG] %s changed %d generic setting(s)"):format(actor, #changed))
        end

        return true, changed
    end

    if not peerSet[target] then return false, { _ = "that script is not accepting settings" } end

    local ok, response = pcall(function()
        return exports[target]:ggSettingsApply(changes, actor, data.revision)
    end)

    if not ok or type(response) ~= "table" then
        print(("^1[gg_lib] settings save to '%s' failed: %s^0"):format(target, response))
        return false, { _ = "the target script rejected the write" }
    end

    if not response.ok then return false, response.result end

    local changed = response.result

    if #resets > 0 then
        local resetOk, resetResponse = pcall(function()
            return exports[target]:ggSettingsReset(resets, actor)
        end)

        if not resetOk or type(resetResponse) ~= "table" then
            return false, { _ = "the target script rejected the reset" }
        end

        if not resetResponse.ok then return false, resetResponse.result end

        for index = 1, #resetResponse.result do changed[#changed + 1] = resetResponse.result[index] end
    end

    if #changed > 0 and GlobalState.gg_debug == true then
        print(("[gg_lib] [DEBUG] %s changed %d setting(s) in %s"):format(actor, #changed, target))
    end

    return true, changed
end)

GGCallback.register("gg_lib:settings:reset", function(source, data)
    if type(data) ~= "table" or type(data.resource) ~= "string" or type(data.paths) ~= "table" then
        return false, { _ = "malformed payload" }
    end

    if not Admins.canEdit(source, data.resource) then
        print(("^1[gg_lib] blocked settings RESET on %s from %s^0"):format(data.resource, actorFor(source)))
        return false, { _ = "you do not have permission to change this script" }
    end

    if data.resource == GenericSettings.resource then
        return GenericSettings.reset(data.paths, actorFor(source))
    end

    local ok, response = pcall(function()
        return exports[data.resource]:ggSettingsReset(data.paths, actorFor(source), data.revision)
    end)

    if not ok or type(response) ~= "table" then
        return false, { _ = "the target script rejected the reset" }
    end

    return response.ok, response.result
end)

local function forget(resource)
    if Locales then Locales.forget(resource) end

    -- Read again on the next ask, but an unchanged page keeps its stamp.
    if described[resource] then described[resource].key = nil end

    legacy[resource] = nil
    starts[resource] = (starts[resource] or 0) + 1
end

AddEventHandler("onResourceStart", function(resource)
    forget(resource)

    if resource == RESOURCE then return end

    SetTimeout(2000, function()
        setPeer(resource, carriesSettings(resource))
    end)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == RESOURCE then return end

    forget(resource)
    setPeer(resource, false)
end)

-- A script whose settings module loads after it started says so itself.
AddEventHandler("gg_lib:settings:peer", function(resource)
    if type(resource) ~= "string" then return end

    setPeer(resource, carriesSettings(resource))
end)

CreateThread(function()
    Wait(2000)
    scanPeers()
end)

-- 1.0.31. What each row of a list says on its line: a dot and a short count (the script's
-- row_status, through its ggSettingsRowStatus export). Asked for when the Studio shows the
-- list, so a count that moves ("32 machines") is never held in the cached page. A script
-- that predates it answers nothing and its rows say nothing more than before.
GGCallback.register("gg_lib:settings:row_status", function(source, data)
    if type(data) ~= "table" or type(data.resource) ~= "string" or type(data.path) ~= "string" then return false end
    if not Admins.canView(source, data.resource) then return false end
    if GetResourceState(data.resource) ~= "started" or not importsLib(data.resource) then return false end

    local rows = type(data.rows) == "table" and data.rows or nil

    local ok, status = pcall(function()
        return exports[data.resource]:ggSettingsRowStatus(data.path, rows)
    end)

    if not ok or type(status) ~= "table" then return false end

    return true, status
end)

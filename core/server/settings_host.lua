
local peers = {}   -- cached list of resources carrying the settings module

local function canEdit(source)
    return Admins.canEdit(source)
end

local function canView(source)
    return Admins.canView(source)
end

local function actorFor(source)
    return Admins.actor(source)
end

local function scanPeers()
    local found = {}

    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)

        if resource and resource ~= "gg_lib" and GetResourceState(resource) == "started" then
            local ok, alive = pcall(function()
                return exports[resource]:ggSettingsPing()
            end)

            if ok and alive == true then
                found[#found + 1] = resource
            end
        end
    end

    table.sort(found)
    peers = found

    return peers
end

local function checkNeeds(payload)
    local requires = payload.requires

    payload.requires = nil

    if type(requires) ~= "table" then return end

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

    if #warnings > 0 then payload.warnings = warnings end
end

local function describePeers(source)
    local scripts = {}

    local function admit(payload)
        if type(payload) ~= "table" then return end
        if source and not Admins.canView(source, payload.resource) then return end

        payload.can_edit = source == nil or Admins.canEdit(source, payload.resource)

        checkNeeds(payload)

        if Locales then payload = Locales.schema(payload) end
        scripts[#scripts + 1] = payload
    end

    for index = 1, #peers do
        local resource = peers[index]

        local ok, payload = pcall(function()
            return exports[resource]:ggSettingsDescribe()
        end)

        if ok then admit(payload) end
    end

    local ok, generic = pcall(GenericSettings.describe)
    if ok then admit(generic) end

    table.sort(scripts, function(left, right)
        local orderLeft  = left.order or 100
        local orderRight = right.order or 100

        if orderLeft ~= orderRight then return orderLeft < orderRight end

        return (left.label or "") < (right.label or "")
    end)

    return scripts
end

local function openFor(source, focus)
    if source == 0 then
        print("[gg_lib] /ggsettings has no console UI; run it in game")
        return
    end

    if not canView(source) then
        TriggerClientEvent("gg_lib:settings:access", source, {
            identifier = Admins.license2(source) or "",
            file       = ("%s/server_config.lua"):format(GetResourcePath(GetCurrentResourceName()) or "gg_lib"),
        })

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

GGCallback.register("gg_lib:settings:fetch", function(source)
    if not canView(source) then
        print(("^3[gg_lib] blocked settings fetch from %s -- not an admin^0"):format(actorFor(source)))
        return false
    end

    local role = Admins.roleOf(source)
    local tools = {}

    for _, tool in ipairs(Roles.tools) do
        if Roles.can(role, tool.id) then tools[#tools + 1] = tool.id end
    end

    return true, {
        scripts    = describePeers(source),
        can_edit   = canEdit(source),
        can_manage = Admins.canManage(source),
        role       = role,
        role_label = (Roles.get(role) or {}).label,
        tools      = tools,
        theme    = GenericSettings.get("theme.primary_color"),
        fade     = GenericSettings.get("theme.fade_on_hover_out"),
        fade_to  = GenericSettings.get("theme.fade_opacity"),
        home     = HomeFeed and HomeFeed.current() or nil,
        ui_lang  = Locales and Locales.strings() or nil,
    }
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

        if #changed > 0 then
            print(("[gg_lib] %s changed %d generic setting(s)"):format(actor, #changed))
        end

        return true, changed
    end

    local known = false

    for index = 1, #peers do
        if peers[index] == target then known = true break end
    end

    if not known then return false, { _ = "that script is not accepting settings" } end

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

    if #changed > 0 then
        print(("[gg_lib] %s changed %d setting(s) in %s"):format(actor, #changed, target))
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

AddEventHandler("onResourceStart", function(resource)
    if Locales then Locales.forget(resource) end
    SetTimeout(2000, scanPeers)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == "gg_lib" then return end

    if Locales then Locales.forget(resource) end
    SetTimeout(100, scanPeers)
end)


local open = false

GG_PAUSE_GUARD = GG_PAUSE_GUARD or { holders = 0 }

function GG_PAUSE_GUARD.acquire()
    GG_PAUSE_GUARD.holders = GG_PAUSE_GUARD.holders + 1

    if GG_PAUSE_GUARD.holders > 1 then return end

    CreateThread(function()
        while GG_PAUSE_GUARD.holders > 0 do
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)

            if IsPauseMenuActive() then
                SetFrontendActive(false)
            end

            Wait(0)
        end
    end)
end

function GG_PAUSE_GUARD.release()
    GG_PAUSE_GUARD.holders = math.max(0, GG_PAUSE_GUARD.holders - 1)
end

RegisterNetEvent("gg_lib:settings:access", function(data)
    open = true
    SetNuiFocus(true, true)
    GG_PAUSE_GUARD.acquire()

    SendNUIMessage({
        action = "settings_access",
        data = {
            IDENTIFIER = data and data.identifier or "",
            FILE       = data and data.file or "",
        },
    })
end)

RegisterNetEvent("gg_lib:settings:open", function(data)
    local ok, payload = GGCallback.await("gg_lib:settings:fetch")

    if not ok or type(payload) ~= "table" then
        GGPopup.flash("Settings are not available right now.")
        return
    end

    open = true
    SetNuiFocus(true, true)
    GG_PAUSE_GUARD.acquire()

    TriggerServerEvent("gg_lib:presence:enter")

    SendNUIMessage({
        action = "settings_open",
        data = {
            SCRIPTS  = payload.scripts,
            CAN_EDIT = payload.can_edit == true,
            CAN_MANAGE = payload.can_manage == true,
            ROLE     = payload.role,
            ROLE_LABEL = payload.role_label,
            TOOLS    = payload.tools,
            FOCUS    = data and data.focus or nil,
            UI_THEME = payload.theme,
            UI_FADE  = payload.fade,
            UI_FADE_TO = payload.fade_to,
            LIB_VERSION = GetResourceMetadata(GetCurrentResourceName(), "version", 0),
            UI_LANG  = payload.ui_lang,
        },
    })

    if type(payload.home) == "table" then
        SendNUIMessage({ action = "home_feed", data = payload.home })
    end
end)

RegisterNetEvent("gg_lib:home:feed", function(feed)
    if type(feed) ~= "table" then return end

    SendNUIMessage({ action = "home_feed", data = feed })
end)

RegisterNUICallback("settings_save", function(data, cb)
    local ok, result = GGCallback.await("gg_lib:settings:save", {
        resource = data and data.resource,
        changes  = data and data.changes,
        resets   = data and data.resets,
        revision = data and data.revision,
    })

    cb({ ok = ok == true, errors = ok and nil or result, changed = ok and result or nil })
end)

RegisterNUICallback("settings_reset", function(data, cb)
    local ok, result = GGCallback.await("gg_lib:settings:reset", {
        resource = data and data.resource,
        paths    = data and data.paths,
    })

    cb({ ok = ok == true, errors = ok and nil or result, changed = ok and result or nil })
end)

local actionToken = 0
local actionWaiting = {}

AddEventHandler("gg_lib:settings:actionResult", function(token, ok, message)
    local waiting = actionWaiting[token]
    if not waiting then return end

    actionWaiting[token] = nil
    waiting:resolve({ ok = ok == true, message = message })
end)

AddEventHandler("gg_lib:settings:rowActionResult", function(token, ok, value)
    local waiting = actionWaiting[token]
    if not waiting then return end

    actionWaiting[token] = nil

    waiting:resolve({ ok = ok == true, value = ok and value or nil, message = (not ok) and value or nil })
end)

RegisterNUICallback("settings_row_action", function(data, cb)
    local resource = type(data) == "table" and data.resource or nil
    local id = type(data) == "table" and data.action or nil
    local row = type(data) == "table" and data.row or nil

    if type(resource) ~= "string" or type(id) ~= "string" or type(row) ~= "table" then
        cb({ ok = false, message = "malformed request" })
        return
    end

    actionToken = actionToken + 1

    local token = actionToken
    local answer = promise.new()

    actionWaiting[token] = answer

    TriggerEvent("gg_lib:settings:rowAction", resource, id, row, token)

    SetTimeout(900000, function()
        if actionWaiting[token] then
            actionWaiting[token] = nil
            answer:resolve({ ok = false, message = "the script did not answer" })
        end
    end)

    local answered = Citizen.Await(answer)

    if not answered.ok and answered.message then
        GGPopup.flash(tostring(answered.message))
    end

    cb(answered)
end)

RegisterNUICallback("settings_model_check", function(data, cb)
    local model = type(data) == "table" and data.model or nil

    if type(model) ~= "string" or model == "" then
        cb({ ok = false })
        return
    end

    local hash = joaat(model)

    if not IsModelInCdimage(hash) then
        cb({ ok = false })
        return
    end

    RequestModel(hash)

    for _ = 1, 200 do
        if HasModelLoaded(hash) then break end
        Wait(10)
    end

    if not HasModelLoaded(hash) then
        cb({ ok = false })
        return
    end

    local answer = { ok = true }

    local label = GetDisplayNameFromVehicleModel(hash)

    if label and label ~= "" and label ~= "CARNOTFOUND" then
        local text = GetLabelText(label)
        answer.label = (text and text ~= "NULL" and text) or label
    end

    SetModelAsNoLongerNeeded(hash)

    cb(answer)
end)

RegisterNUICallback("settings_action", function(data, cb)
    local resource = type(data) == "table" and data.resource or nil
    local path = type(data) == "table" and data.path or nil

    if type(resource) ~= "string" or type(path) ~= "string" then
        cb({ ok = false, message = "malformed request" })
        return
    end

    actionToken = actionToken + 1

    local token = actionToken
    local answer = promise.new()

    actionWaiting[token] = answer

    TriggerEvent("gg_lib:settings:action", resource, path, token)

    SetTimeout(120000, function()
        if actionWaiting[token] then
            actionWaiting[token] = nil
            answer:resolve({ ok = false, message = "the script did not answer" })
        end
    end)

    cb(Citizen.Await(answer))
end)

RegisterNUICallback("settings_refresh", function(_, cb)
    local ok, payload = GGCallback.await("gg_lib:settings:fetch")

    if not ok or type(payload) ~= "table" then
        cb({ ok = false })
        return
    end

    cb({
        ok = true,
        SCRIPTS = payload.scripts,
        CAN_EDIT = payload.can_edit == true,
        CAN_MANAGE = payload.can_manage == true,
        ROLE = payload.role,
        ROLE_LABEL = payload.role_label,
        TOOLS = payload.tools,
        UI_THEME = payload.theme,
        UI_FADE = payload.fade,
        UI_FADE_TO = payload.fade_to,
    })
end)

RegisterNetEvent("gg_lib:generic:sync", function(payload)
    local values = payload and payload.values
    if not values then return end

    if values["theme.primary_color"] == nil and values["theme.fade_on_hover_out"] == nil and values["theme.fade_opacity"] == nil then
        return
    end

    SendNUIMessage({
        action = "settings_theme",
        data   = {
            UI_THEME   = values["theme.primary_color"],
            UI_FADE    = values["theme.fade_on_hover_out"],
            UI_FADE_TO = values["theme.fade_opacity"],
        },
    })
end)

RegisterNUICallback("admins_fetch", function(_, cb)
    local ok, payload = GGCallback.await("gg_lib:admins:fetch")

    cb({ ok = ok == true, ADMINS = ok and payload.admins or nil, PLAYERS = ok and payload.players or nil, ROLES = ok and payload.roles or nil })
end)

RegisterNUICallback("groups_fetch", function(_, cb)
    local ok, payload = GGCallback.await("gg_lib:groups:fetch")

    cb({ ok = ok == true, GROUPS = ok and payload.groups or nil, KINDS = ok and payload.kinds or nil })
end)

RegisterNUICallback("admins_detail", function(data, cb)
    local ok, detail = GGCallback.await("gg_lib:admins:detail", { identifier = data and data.identifier })

    cb({ ok = ok == true, DETAIL = ok and detail or nil })
end)

RegisterNUICallback("bridge_fetch", function(_, cb)
    local ok, payload = GGCallback.await("gg_lib:bridge:fetch")

    cb({ ok = ok == true, DATA = ok and payload or nil })
end)

RegisterNUICallback("bridge_set_provider", function(data, cb)
    local ok, err = GGCallback.await("gg_lib:bridge:setProvider", {
        path  = data and data.path,
        value = data and data.value,
    })

    cb({ ok = ok == true, error = not ok and err or nil })
end)

local testChoice = {}
local testReady = false

local function ensureInterface()
    if testReady then return true end

    settings = settings or {}
    settings.generic = settings.generic or {}
    settings.generic.get = function(path) return testChoice[path] end

    gg = gg or {}

    for _, path in ipairs({ "modules/display/client.lua", "modules/menu/client.lua" }) do
        local source = LoadResourceFile(GetCurrentResourceName(), path)
        if not source then return false end

        local chunk = load(source, ("@@gg_lib/%s"):format(path), "t")
        if not chunk then return false end

        if not pcall(chunk) then return false end
    end

    testReady = true

    return true
end

local MENU_WAIT_MS = 30000

local function runTest(id)
    if id == "notifications" then
        gg.display.notify({
            title   = "gg_lib",
            msg     = "Notifications are wired up.",
            status  = "success",
            timeout = 4000,
            icon    = "plug",
        })

        Wait(2600)
    elseif id == "progressbar" then
        gg.display.ProgressBar({ label = "Testing progress bars", duration = 3000 })
    elseif id == "textui" then
        gg.display.DoTextui({ msg = "gg_lib text UI test", position = "left" })
        Wait(3000)
        gg.display.RemoveTextui()
    elseif id == "context" then
        gg.menu.open({
            id    = "gg_lib_bridge_test",
            title = "gg_lib",
        }, {
            { title = "Context menus are wired up", description = "Close this to return to the editor", icon = "plug" },
        })

        Wait(400)

        local deadline = GetGameTimer() + MENU_WAIT_MS

        while GetGameTimer() < deadline do
            if not gg.menu.getOpenContextMenu() then break end

            Wait(200)
        end
    end
end

RegisterNUICallback("bridge_test", function(data, cb)
    local id = data and data.id

    if not ensureInterface() then
        cb({ ok = false })
        return
    end

    if data and data.path then testChoice[data.path] = data.value end

    for _, extra in ipairs((data and data.tuning) or {}) do
        if extra.path then testChoice[extra.path] = extra.value end
    end

    SetNuiFocus(false, false)

    CreateThread(function()
        local ok = pcall(runTest, id)

        if open then SetNuiFocus(true, true) end

        cb({ ok = ok })
    end)
end)

for _, entry in ipairs({
    { nui = "admins_set_role",    channel = "gg_lib:admins:setRole" },
    { nui = "admins_save_role",   channel = "gg_lib:admins:saveRole" },
    { nui = "admins_delete_role", channel = "gg_lib:admins:deleteRole" },
}) do
    RegisterNUICallback(entry.nui, function(data, cb)
        local ok, result = GGCallback.await(entry.channel, data)

        cb({
            ok      = ok == true,
            error   = not ok and result or nil,
            ADMINS  = ok and result.admins or nil,
            PLAYERS = ok and result.players or nil,
            ROLES   = ok and result.roles or nil,
        })
    end)
end

RegisterNUICallback("admins_grant", function(data, cb)
    local ok, result = GGCallback.await("gg_lib:admins:grant", {
        player     = data and data.player,
        identifier = data and data.identifier,
    })

    cb({
        ok      = ok == true,
        error   = not ok and result or nil,
        ADMINS  = ok and result.admins or nil,
        PLAYERS = ok and result.players or nil,
        ROLES   = ok and result.roles or nil,
    })
end)

RegisterNUICallback("admins_revoke", function(data, cb)
    local ok, result = GGCallback.await("gg_lib:admins:revoke", {
        identifier = data and data.identifier,
    })

    cb({
        ok      = ok == true,
        error   = not ok and result or nil,
        ADMINS  = ok and result.admins or nil,
        PLAYERS = ok and result.players or nil,
        ROLES   = ok and result.roles or nil,
    })
end)

RegisterNUICallback("logs_fetch", function(data, cb)
    local ok, payload = GGCallback.await("gg_lib:logs:fetch", {
        page     = data and data.page,
        size     = data and data.size,
        search   = data and data.search,
        resource = data and data.resource,
        kind     = data and data.kind,
    })

    cb({
        ok        = ok == true,
        ROWS      = ok and payload.rows or nil,
        TOTAL     = ok and payload.total or 0,
        ACTORS    = ok and payload.actors or nil,
        PLAYERS   = ok and payload.players or nil,
        SCRIPTS   = ok and payload.scripts or nil,
        ACTIONS   = ok and payload.actions or nil,
        ROUTES    = ok and payload.routes or nil,
        RETENTION = ok and payload.retention or nil,
    })
end)

RegisterNUICallback("logs_retention", function(data, cb)
    local ok = GGCallback.await("gg_lib:logs:setRetention", data and data.days)

    cb({ ok = ok == true })
end)

RegisterNUICallback("actions_save_route", function(data, cb)
    local ok, payload = GGCallback.await("gg_lib:actions:saveRoute", data)

    cb({ ok = ok == true, ROUTES = ok and payload and payload.routes or nil, ERR = payload and payload.err or nil })
end)

RegisterNUICallback("actions_delete_route", function(data, cb)
    local ok, payload = GGCallback.await("gg_lib:actions:deleteRoute", data and data.id)

    cb({ ok = ok == true, ROUTES = ok and payload and payload.routes or nil })
end)

RegisterNUICallback("actions_test_route", function(data, cb)
    local ok = GGCallback.await("gg_lib:actions:test", data and data.id)

    cb({ ok = ok == true })
end)

RegisterNUICallback("settings_close", function(_, cb)
    if gg and gg.tool and gg.tool.isActive() then
        cb({})
        return
    end

    if open then
        GG_PAUSE_GUARD.release()
        TriggerServerEvent("gg_lib:presence:leave")
    end

    open = false
    SetNuiFocus(false, false)
    cb({})
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= "gg_lib" then return end
    if open then SetNuiFocus(false, false) end

    GG_PAUSE_GUARD.holders = 0
end)

RegisterNetEvent("gg_lib:presence:sync", function(list)
    SendNUIMessage({ action = "presence", data = { EDITORS = list, ME = GetPlayerServerId(PlayerId()) } })
end)

local framework_core = nil

gg.display = gg.display or {}

local DEFAULT = "ox"

local function provider(path, fallback)
    local chosen = settings and settings.generic and settings.generic.get(path)

    return (type(chosen) == "string" and chosen ~= "" and chosen) or fallback
end

-- ox_lib's global `lib` exists only in a script that loads @ox_lib/init.lua. A gg_lib script
-- doesn't have to load it (gg_mlo_belladonna doesn't), and there `lib.notify` errored (gg_lib#9).
-- ox_lib exports every one of these calls, so go through its exports, whoever the caller is.
-- Returns false when ox_lib isn't running, so the caller can fall back.
local function ox(name, ...)
    if GetResourceState("ox_lib") ~= "started" then return false end

    return true, exports.ox_lib[name](nil, ...)
end

-- Without ox_lib: GTA's own notice feed and help text, so the message still shows.
-- A text component holds at most 99 bytes; split longer text without cutting a UTF-8 character.
local function addText(text)
    local start = 1
    while start <= #text do
        local stop = math.min(#text, start + 95)
        while stop > start and stop < #text and (text:byte(stop + 1) & 0xC0) == 0x80 do stop = stop - 1 end
        AddTextComponentSubstringPlayerName(text:sub(start, stop))
        start = stop + 1
    end
end

local function feedNotice(message)
    local text = tostring(message.msg or "")
    if message.title and message.title ~= "" then
        text = ("~h~%s~h~~n~%s"):format(message.title, text)
    end

    BeginTextCommandThefeedPost("STRING")
    addText(text)
    EndTextCommandThefeedPostTicker(false, true)
end

local helpText = nil

local function showHelp(msg)
    local drawing = helpText ~= nil
    helpText = tostring(msg or "")
    if drawing then return end

    CreateThread(function()
        while helpText do
            BeginTextCommandDisplayHelp("STRING")
            addText(helpText)
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        end
    end)
end

local function hideHelp()
    if not helpText then return end

    helpText = nil
    ClearAllHelpMessages()
end

gg.display.notify = function(message)
    local _type = provider("interface.notifications", DEFAULT)
    if _type == 'ox' then
        if not ox("notify", { title = message.title, description = message.msg, duration = message.timeout, type = message.status, icon = message.icon }) then
            feedNotice(message)
        end
    elseif _type == 'mythic' then
        return exports['mythic_notify']:SendAlert(message.status, message.msg)
    elseif _type == 'old_mythic' then
        return exports['mythic_notify']:DoHudText(message.status, message.msg)
    elseif _type == 'pNotify' then
        return exports.pNotify:SendNotification({text = message.msg, type = message.status, timeout = message.timeout})
    elseif _type == 'brutal' then
        return exports['brutal_notify']:SendAlert( message.title, message.msg, message.timeout, message.status)
    elseif _type == 'okok' then
        return exports['okokNotify']:Alert(message.title, message.msg, message.timeout, message.status, false)
    elseif _type == 'stNotify' then
        return exports['stNotify']:Notify(message.status, message.msg, message.title)
    elseif _type == 'sd' then
        return exports['sd-notify']:Notify(message.title, message.msg, message.timeout, message.status, message.position, false, false)
    elseif _type == 'wasabi' then
        return exports.wasabi_notify:notify(message.status, message.msg, message.timeout, message.status)
    elseif _type == 'qb' then
        return TriggerEvent('QBCore:Notify', message.msg, message.status, message.timeout)
    elseif _type == 'esx' then
        return TriggerEvent('esx:showNotification', message.msg)
    elseif _type == 'custom' then
    end
end

gg.display.DoTextui = function(text)
    local _type = provider("interface.textui", DEFAULT)
    if _type == 'ox' then
        if not ox("showTextUI", text.msg, { position = provider("interface.ox_textui_position", "right-center") }) then
            showHelp(text.msg)
        end
    elseif _type == 'jg' then
        return exports['jg-textui']:DrawText(text.msg)
    elseif _type == 'qb' then
        return exports['qb-core']:DrawText(text.msg, text.position)
    elseif _type == 'cd' then
        return TriggerEvent('cd_drawtextui:ShowUI', 'show', text.msg)
    elseif _type == 'lab' then
        return exports['lab-HintUI']:Show(text.msg)
    elseif _type == 'custom' then
    end
end

gg.display.RemoveTextui = function()
    local _type = provider("interface.textui", DEFAULT)
    if _type == 'ox' then
        ox("hideTextUI")
        hideHelp()
    elseif _type == 'jg' then
        return exports['jg-textui']:HideText()
    elseif _type == 'qb' then
        return exports['qb-core']:HideText()
    elseif _type == 'cd' then
        return TriggerEvent('cd_drawtextui:HideUI')
    elseif _type == 'lab' then
        return exports['lab-HintUI']:Hide()
    elseif _type == 'custom' then
    end
end

RegisterNetEvent(GetCurrentResourceName()..':client:notify', function(data)
    gg.display.notify(data)
end)

-- ox_lib's bar or circle; without ox_lib, gg_lib's own progress bar.
local function oxProgress(data)
    local ran, done
    if provider("interface.ox_progress_style", "circle") == "bar" then
        ran, done = ox("progressBar", {
            duration = data.duration,
            label = data.label,
            canCancel = true,
            disable = {
                car = true,
            },
        })
    else
        ran, done = ox("progressCircle", {
            duration = data.duration,
            label = data.label,
            canCancel = true,
            position = provider("interface.ox_progress_position", "bottom"),
            disable = {
                car = true,
            },
        })
    end

    if not ran then
        return exports.gg_lib:ggProgress(data) == true
    end

    return done == true
end

gg.display.ProgressBar = function(data)
    local _type = provider("interface.progressbar", DEFAULT)
    local success = false
    local p = promise.new()

    if _type == "gg" then
        return exports.gg_lib:ggProgress(data) == true
    end
    if _type == "qb" and GetResourceState("qb-core") == "started" then
        if not framework_core then framework_core = exports['qb-core']:GetCoreObject() end
        framework_core.Functions.Progressbar("gg_lib_progressbar", data.label, data.duration, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            p:resolve(true)
        end, function()
            p:resolve(false)
        end)
        return Citizen.Await(p)
    elseif _type == "esx" and GetResourceState("es_extended") == "started" then
        if not framework_core then framework_core = exports.es_extended:getSharedObject() end
        framework_core.Progressbar(data.label, data.duration,{
            FreezePlayer = false,
            onFinish = function()
                p:resolve(true)
            end, onCancel = function()
                p:resolve(false)
            end
        })
        return Citizen.Await(p)
    else
        success = oxProgress(data)
    end

    return success
end

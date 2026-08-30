gg.nui = gg.nui or {}

gg.nui.emit = function(event, data)
    SendNUIMessage({
        action  = event,
        data = data,
    })
end

local busy = false

gg.nui.isBusy = function()
    return busy
end

gg.nui.toggle = function(bool, focus)
    focus = focus or {}
    SetNuiFocus(focus[1] or bool, focus[2] or bool)

    busy = bool and true or false

    local panel = rawget(gg, "panel")

    if not panel then return end

    if bool then panel.suspend() else panel.resume() end
end

RegisterNUICallback('hideUI', function(_, cb)
    gg.player.ToggleTablet(false)
    TriggerEvent(GetCurrentResourceName().."client:forcecloseui")
    gg.nui.toggle(false, false)
    cb({})
end)

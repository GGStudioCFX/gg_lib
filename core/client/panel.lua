
local state = { enabled = false, open = false }

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local placement = { side = "right", height = 50 }

local function readPlacement(values)
    if type(values) ~= "table" then return false end

    local side   = values["popup.panel_side"]
    local height = tonumber(values["popup.panel_height"])
    local moved  = false

    if (side == "left" or side == "right") and side ~= placement.side then
        placement.side = side
        moved = true
    end

    if height then
        height = math.max(5, math.min(95, height))

        if height ~= placement.height then
            placement.height = height
            moved = true
        end
    end

    return moved
end

local function update(payload)
    if type(payload) ~= "table" then return end

    if payload.enabled ~= nil then state.enabled = payload.enabled == true end
    if payload.open ~= nil then state.open = payload.open == true end

    if payload.enabled == true then
        payload.side   = placement.side
        payload.height = placement.height
    end

    send("panel_update", payload)
end

exports("ggPanelUpdate", update)

local function announce()
    TriggerEvent("gg_lib:panel:open", state.open)
end

exports("ggPanelToggle", function(open)
    if open == nil then open = not state.open end

    state.open = open == true

    send("panel_update", { open = state.open })
    announce()

    return state.open
end)

exports("ggPanelHide", function()
    state.enabled = false
    state.open    = false

    send("panel_update", { enabled = false, open = false })
end)

exports("ggPanelIsOpen", function()
    return state.open
end)

RegisterNUICallback("panel_toggled", function(data, cb)
    cb({ ok = true })

    if type(data) == "table" then state.open = data.open == true end

    announce()
end)

CreateThread(function()
    Wait(2500)

    local ok, answered, snapshot = pcall(GGCallback.await, "gg_lib:generic:snapshot")

    if ok and answered and type(snapshot) == "table" then readPlacement(snapshot.values) end
end)

RegisterNetEvent("gg_lib:generic:sync", function(payload)
    if not readPlacement(payload and payload.values) then return end
    if not state.enabled then return end

    send("panel_update", { side = placement.side, height = placement.height })
end)

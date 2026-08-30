
local RESOURCE = GetCurrentResourceName()

local running = nil

local BLOCKED = {
    24, 25, 257, 263, 264, -- attacking
    22,                    -- jump
    75,                    -- exit vehicle
    23,                    -- enter vehicle
}

local function blockWhileRunning()
    CreateThread(function()
        while running do
            for index = 1, #BLOCKED do
                DisableControlAction(0, BLOCKED[index], true)
            end

            Wait(0)
        end
    end)
end

local function finish(ok)
    local run = running

    if not run then return end

    running = nil

    SendNUIMessage({ action = "gg_progress", data = { open = false } })

    run.answer:resolve(ok == true)
end

function GGProgress(data)
    if type(data) ~= "table" then return false end

    if running then return false end

    local duration = math.max(1, math.floor(tonumber(data.duration) or 0))
    local canCancel = data.canCancel ~= false

    running = {
        answer = promise.new(),
        canCancel = canCancel,
    }

    SendNUIMessage({
        action = "gg_progress",
        data = {
            open = true,
            label = tostring(data.label or ""),
            duration = duration,
            canCancel = canCancel,
        },
    })

    blockWhileRunning()

    SetTimeout(duration, function() finish(true) end)

    return Citizen.Await(running.answer)
end

exports("ggProgress", function(data)
    return GGProgress(data)
end)

RegisterNUICallback("gg_progress_cancel", function(_, cb)
    cb({ ok = true })

    if running and running.canCancel then finish(false) end
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource == RESOURCE then finish(false) end
end)

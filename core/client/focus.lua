
GG_VIEWER = GG_VIEWER or {}

local LOOK_KEY  = 19   -- left alt
local CLOSE_KEY = 200  -- escape

local BLOCKED = {
    24, 25, 140, 141, 142, 257, 263, 264,
    22, 23, 75,
    199, 200,
    19,
}

local current = nil
local cursor  = true

local function tellPage(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function setCursor(on)
    if on == cursor then return end

    cursor = on

    SetNuiFocus(on, on)

    tellPage("viewer_look", { LOOKING = not on })
end

GG_VIEWER.setCursor = setCursor

function GG_VIEWER.open(name)
    if current == name then return end

    current = name
    cursor  = true

    SetNuiFocus(true, true)

    CreateThread(function()
        while current == name do
            for index = 1, #BLOCKED do
                DisableControlAction(0, BLOCKED[index], true)
            end

            if not cursor then
                if IsDisabledControlJustPressed(0, LOOK_KEY) then setCursor(true) end

                if IsDisabledControlJustPressed(0, CLOSE_KEY) then
                    tellPage("viewer_close", { NAME = name })

                    break
                end
            end

            if IsPauseMenuActive() then SetPauseMenuActive(false) end

            Wait(0)
        end
    end)
end

function GG_VIEWER.close()
    if not current then return end

    current = nil
    cursor  = true

    SetNuiFocus(true, true)
end

function GG_VIEWER.release()
    current = nil
    cursor  = true

    SetNuiFocus(false, false)
end

function GG_VIEWER.isOpen()
    return current ~= nil
end

function GG_VIEWER.looking()
    return current ~= nil and not cursor
end

RegisterNUICallback("viewer_look", function(data, cb)
    cb({ ok = true })

    if not current then return end

    setCursor(not (data and data.free == true))
end)

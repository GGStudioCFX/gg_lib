
gg = gg or {}

GG_EDITOR_STAGE = GG_EDITOR_STAGE or {}

local RESOURCE = GetCurrentResourceName()

local LOAD_TIMEOUT_MS = 8000

local SLOTS = {
    { id = 0,  label = "Spoiler",        group = "body" },
    { id = 1,  label = "Front Bumper",   group = "body" },
    { id = 2,  label = "Rear Bumper",    group = "body" },
    { id = 3,  label = "Side Skirt",     group = "body" },
    { id = 4,  label = "Exhaust",        group = "body" },
    { id = 5,  label = "Roll Cage",      group = "body" },
    { id = 6,  label = "Grille",         group = "body" },
    { id = 7,  label = "Hood",           group = "body" },
    { id = 8,  label = "Left Fender",    group = "body" },
    { id = 9,  label = "Right Fender",   group = "body" },
    { id = 10, label = "Roof",           group = "body" },
    { id = 27, label = "Trim",           group = "body" },
    { id = 42, label = "Arch Cover",     group = "body" },
    { id = 43, label = "Aerial",         group = "body" },
    { id = 44, label = "Trim B",         group = "body" },
    { id = 45, label = "Fuel Tank",      group = "body" },
    { id = 46, label = "Left Door",      group = "body" },
    { id = 47, label = "Right Door",     group = "body" },
    { id = 49, label = "Light Bar",      group = "body" },

    { id = 14, label = "Horn",           group = "interior" },
    { id = 28, label = "Ornaments",      group = "interior" },
    { id = 29, label = "Dashboard",      group = "interior" },
    { id = 30, label = "Dial",           group = "interior" },
    { id = 31, label = "Door Speaker",   group = "interior" },
    { id = 32, label = "Seats",          group = "interior" },
    { id = 33, label = "Steering Wheel", group = "interior" },
    { id = 34, label = "Shifter",        group = "interior" },
    { id = 35, label = "Plaque",         group = "interior" },
    { id = 36, label = "Speaker",        group = "interior" },
    { id = 37, label = "Trunk",          group = "interior" },
    { id = 38, label = "Hydraulics",     group = "interior" },
    { id = 39, label = "Engine Block",   group = "interior" },
    { id = 40, label = "Air Filter",     group = "interior" },
    { id = 41, label = "Strut",          group = "interior" },
    { id = 19, label = "Subwoofer",      group = "interior" },
    { id = 25, label = "Plate Holder",   group = "interior" },

    { id = 11, label = "Engine",         group = "performance" },
    { id = 12, label = "Brakes",         group = "performance" },
    { id = 13, label = "Transmission",   group = "performance" },
    { id = 15, label = "Suspension",     group = "performance" },
    { id = 16, label = "Armour",         group = "performance" },
}

local WHEEL_TYPES = {
    { id = 0,  label = "Sport" },
    { id = 1,  label = "Muscle" },
    { id = 2,  label = "Lowrider" },
    { id = 3,  label = "SUV" },
    { id = 4,  label = "Offroad" },
    { id = 5,  label = "Tuner" },
    { id = 6,  label = "Bike" },
    { id = 7,  label = "High End" },
    { id = 8,  label = "Benny's Original" },
    { id = 9,  label = "Benny's Bespoke" },
    { id = 10, label = "Open Wheel" },
    { id = 11, label = "Street" },
    { id = 12, label = "Track" },
}

local TOGGLES = {
    { id = 18, label = "Turbo" },
    { id = 20, label = "Tyre Smoke" },
    { id = 22, label = "Xenon Lights" },
}

local WHEEL_SLOT = 23
local HORN_SLOT  = 14

local target  = nil
local heading = 0.0

local job = nil

local function say(message)
    print(("[gg_lib] %s"):format(message))
end

local BLOCKED = {
    24, 25, 140, 141, 142, 257, 263, 264,  -- swinging and shooting
    22, 23, 75,                            -- jump, in, out
    71, 72, 63, 64,                        -- driving
    199, 200,                              -- pause
}

local KEY_TURN = 1.4

local blocking = false

local function blockInput(on)
    if on == blocking then return end

    blocking = on

    if not on then return end

    CreateThread(function()
        while blocking do
            for index = 1, #BLOCKED do
                DisableControlAction(0, BLOCKED[index], true)
            end

            if GG_VIEWER.looking() and target and DoesEntityExist(target) then
                local turn = 0.0

                if IsDisabledControlPressed(0, 34) then turn = turn - KEY_TURN end   -- A
                if IsDisabledControlPressed(0, 35) then turn = turn + KEY_TURN end   -- D

                if turn ~= 0.0 then
                    heading = (heading + turn) % 360.0

                    SetEntityHeading(target, heading)
                end
            end

            if IsPauseMenuActive() then SetPauseMenuActive(false) end

            Wait(0)
        end
    end)
end

local SMOKE_SLOT = 20

local function pretty(text)
    return (text:gsub("(%a[%w']*)", function(word)
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end))
end

local function modLabel(vehicle, slot, value)
    if value < 0 then return "Stock" end

    local key = GetModTextLabel(vehicle, slot, value)

    if key and key ~= "" then
        local text = GetLabelText(key)

        if text and text ~= "" and text ~= "NULL" and text ~= key then return text end

        local name = key:gsub("^CMOD_", ""):gsub("_", " "):gsub("^%s+", "")

        if name ~= "" then return pretty(name) end
    end

    return ("Option %d"):format(value + 1)
end

local function scan(vehicle)
    SetVehicleModKit(vehicle, 0)

    local slots = {}

    for index = 1, #SLOTS do
        local slot  = SLOTS[index]
        local count = GetNumVehicleMods(vehicle, slot.id)

        if count > 0 then
            local options = { { value = -1, label = "Stock" } }

            for value = 0, count - 1 do
                options[#options + 1] = { value = value, label = modLabel(vehicle, slot.id, value) }
            end

            slots[#slots + 1] = {
                id      = slot.id,
                label   = slot.label,
                group   = slot.group,
                current = GetVehicleMod(vehicle, slot.id),
                options = options,
            }
        end
    end

    local toggles = {}

    for index = 1, #TOGGLES do
        local toggle = TOGGLES[index]

        toggles[#toggles + 1] = { id = toggle.id, label = toggle.label, on = IsToggleModOn(vehicle, toggle.id) }
    end

    local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(vehicle)

    local smoke = {
        on = IsToggleModOn(vehicle, SMOKE_SLOT),
        colour = { r = smokeR or 255, g = smokeG or 255, b = smokeB or 255 },
    }

    local extras = {}

    for extra = 0, 20 do
        if DoesExtraExist(vehicle, extra) then
            extras[#extras + 1] = { id = extra, on = IsVehicleExtraTurnedOn(vehicle, extra) }
        end
    end

    local wheelCount = GetNumVehicleMods(vehicle, WHEEL_SLOT)
    local wheels     = { { value = -1, label = "Stock" } }

    for value = 0, wheelCount - 1 do
        wheels[#wheels + 1] = { value = value, label = modLabel(vehicle, WHEEL_SLOT, value) }
    end

    local primary, secondary = GetVehicleColours(vehicle)
    local pearl, wheelColour = GetVehicleExtraColours(vehicle)

    local neonR, neonG, neonB = GetVehicleNeonLightsColour(vehicle)
    local xenonColour         = GetVehicleXenonLightsColor and GetVehicleXenonLightsColor(vehicle) or -1
    local nativeLiveries      = math.max(0, GetVehicleLiveryCount(vehicle))
    local modLiveries         = math.max(0, GetNumVehicleMods(vehicle, 48))

    return {
        model      = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower(),
        slots      = slots,
        toggles    = toggles,
        extras     = extras,
        wheels     = wheels,
        wheelType  = GetVehicleWheelType(vehicle),
        wheelTypes = WHEEL_TYPES,
        wheelMod   = GetVehicleMod(vehicle, WHEEL_SLOT),
        customTyres = GetVehicleModVariation(vehicle, WHEEL_SLOT),
        colours = {
            primary   = primary,
            secondary = secondary,
            pearl     = pearl,
            wheel     = wheelColour,
            interior  = GetVehicleInteriorColour(vehicle),
            dash      = GetVehicleDashboardColour(vehicle),
        },
        smoke   = smoke,
        tint    = GetVehicleWindowTint(vehicle),
        livery  = {
            current = GetVehicleLivery(vehicle),
            count = nativeLiveries,
            modCurrent = GetVehicleMod(vehicle, 48),
            modCount = modLiveries,
        },
        plate   = GetVehicleNumberPlateTextIndex(vehicle),
        xenon   = { on = IsToggleModOn(vehicle, 22), colour = xenonColour },
        neon    = {
            left   = IsVehicleNeonLightEnabled(vehicle, 0),
            right  = IsVehicleNeonLightEnabled(vehicle, 1),
            front  = IsVehicleNeonLightEnabled(vehicle, 2),
            back   = IsVehicleNeonLightEnabled(vehicle, 3),
            colour = { r = neonR, g = neonG, b = neonB },
        },
    }
end

local function publish()
    if not (target and DoesEntityExist(target)) then return end

    SendNUIMessage({ action = "customs_state", data = scan(target) })
end

local function apply(kind, id, value, extra)
    local vehicle = target

    if not (vehicle and DoesEntityExist(vehicle)) then return end

    SetVehicleModKit(vehicle, 0)

    if kind == "mod" then
        SetVehicleMod(vehicle, id, value, extra == true)

        if id == HORN_SLOT then StartVehicleHorn(vehicle, 900, joaat("HELDDOWN"), false) end
    elseif kind == "smokecolour" then
        SetVehicleTyreSmokeColor(vehicle, value.r or 255, value.g or 255, value.b or 255)
    elseif kind == "toggle" then
        ToggleVehicleMod(vehicle, id, value == true)
    elseif kind == "extra" then
        SetVehicleExtra(vehicle, id, not value)
    elseif kind == "wheeltype" then
        SetVehicleWheelType(vehicle, value)

        SetVehicleMod(vehicle, WHEEL_SLOT, -1, false)
    elseif kind == "wheel" then
        SetVehicleMod(vehicle, WHEEL_SLOT, value, extra == true)
    elseif kind == "colour" then
        local primary, secondary = GetVehicleColours(vehicle)
        local pearl, wheel       = GetVehicleExtraColours(vehicle)

        if id == "primary" then SetVehicleColours(vehicle, value, secondary) end
        if id == "secondary" then SetVehicleColours(vehicle, primary, value) end
        if id == "pearl" then SetVehicleExtraColours(vehicle, value, wheel) end
        if id == "wheel" then SetVehicleExtraColours(vehicle, pearl, value) end
        if id == "interior" then SetVehicleInteriorColour(vehicle, value) end
        if id == "dash" then SetVehicleDashboardColour(vehicle, value) end
    elseif kind == "tint" then
        SetVehicleWindowTint(vehicle, value)
    elseif kind == "livery" then
        SetVehicleLivery(vehicle, value)
    elseif kind == "modlivery" then
        SetVehicleMod(vehicle, 48, value, false)
    elseif kind == "plate" then
        SetVehicleNumberPlateTextIndex(vehicle, value)
    elseif kind == "xenoncolour" then
        SetVehicleXenonLightsColor(vehicle, value)
    elseif kind == "neon" then
        SetVehicleNeonLightEnabled(vehicle, id, value == true)
    elseif kind == "neoncolour" then
        SetVehicleNeonLightsColour(vehicle, value.r or 255, value.g or 255, value.b or 255)
    end

    publish()
end

local function clear()
    target = nil

    blockInput(false)
end

local function held()
    return GetVehiclePedIsIn(PlayerPedId(), false)
end

local function finishJob(result)
    local ending = job

    if not ending then return end

    job = nil

    -- Before the car goes, or the props it was wearing are left behind it.
    if GGAttachments and GGAttachments.strip then pcall(GGAttachments.strip, ending.vehicle) end

    GG_EDITOR_STAGE.despawn(ending.vehicle)

    GG_EDITOR_STAGE.leave()

    TriggerEvent("gg_lib:customs:tuneResult", ending.resource, ending.id, result)
end

--- Puts the screen, the controls and the stage back after a run that threw
--- part way through. The half-built job is what wedges the next press.
local function abandonJob(why)
    clear()
    SetNuiFocus(false, false)

    SendNUIMessage({ action = "customs_state", data = { open = false } })

    if job then
        finishJob(why)
    else
        GG_EDITOR_STAGE.leave()
    end
end

local function runJob(resource, id, options)
    if job then return "the vehicle tuner is already open" end
    if target and DoesEntityExist(target) then return "the customs bay is already open" end

    GG_EDITOR_STAGE.enter()

    local vehicle, why = GG_EDITOR_STAGE.spawn(options.vehicle, 210.0)

    if not vehicle then
        GG_EDITOR_STAGE.leave()

        return why
    end

    if type(options.properties) == "table" and next(options.properties) then
        do
            pcall(GGVehicle.setProperties, vehicle, options.properties)
        end
    end

    -- Whatever the vehicle wears in the world, it wears in here: paint chosen
    -- against a bare roof is paint chosen against the wrong car. It is fitted
    -- for looking at only -- moving the kit is its own editor.
    if type(options.props) == "table" and GGAttachments and GGAttachments.fit then
        pcall(GGAttachments.fit, vehicle, options.props)
    end

    job = {
        resource = resource,
        id       = id,
        vehicle  = vehicle,
        -- Nothing has been changed yet, so closing now is a look, not an edit.
        touched  = false,
        title    = options.title,
        subject  = options.subject,
        answer   = promise.new(),
    }

    GG_EDITOR_STAGE.ride(vehicle)

    target  = vehicle
    heading = GetEntityHeading(vehicle)

    blockInput(true)
    SetNuiFocus(true, true)

    local data = scan(vehicle)

    data.open = true
    data.title = job.title
    data.subject = job.subject

    SendNUIMessage({ action = "customs_state", data = data })

    return nil
end

AddEventHandler("gg_lib:customs:tune", function(resource, id, options)
    if type(resource) ~= "string" or id == nil then return end

    TriggerEvent("gg_lib:customs:tuneAccepted", resource, id)

    CreateThread(function()
        if type(options) ~= "table" then
            TriggerEvent("gg_lib:customs:tuneResult", resource, id, "nothing to tune")
            return
        end

        local ok, refusal = pcall(runJob, resource, id, options)

        if not ok then
            say(("customs: %s"):format(tostring(refusal)))

            abandonJob("the vehicle tuner failed to open")
        elseif refusal then
            TriggerEvent("gg_lib:customs:tuneResult", resource, id, refusal)
        end
    end)
end)
RegisterNUICallback("customs_open", function(_, cb)
    cb({ ok = true })

    CreateThread(function()
        local vehicle = held()

        if vehicle == 0 then
            say("get in a vehicle before opening the customs editor")

            SendNUIMessage({ action = "customs_state", data = { missing = true } })

            return
        end

        target  = vehicle
        heading = GetEntityHeading(vehicle)

        blockInput(true)
        publish()
    end)
end)

RegisterNUICallback("customs_apply", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.kind) ~= "string" then return end

    if job then job.touched = true end

    CreateThread(function()
        apply(data.kind, data.id, data.value, data.extra)
    end)
end)

RegisterNUICallback("customs_preview", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" then return end

    local vehicle = target

    if not (vehicle and DoesEntityExist(vehicle)) then return end

    local slot  = data.wheel and WHEEL_SLOT or tonumber(data.id)
    local value = tonumber(data.value)

    if not slot or not value then return end

    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, slot, value, data.extra == true)
end)

RegisterNUICallback("customs_turn", function(data, cb)
    cb({ ok = true })

    if not (target and DoesEntityExist(target)) then return end

    heading = (heading + (tonumber(data and data.by) or 0.0)) % 360.0

    SetEntityHeading(target, heading)
end)

RegisterNUICallback("customs_close", function(_, cb)
    cb({ ok = true })

    local look = nil

    -- Only hand back a look if one was actually chosen. getProperties returns
    -- the vehicle's ENTIRE mod set, which is a superset of the handful of keys
    -- a script usually stores -- so returning it after a look-and-close left
    -- the caller holding a "change" it never made.
    if job and job.touched and target and DoesEntityExist(target) then
        local ok, properties = pcall(GGVehicle.getProperties, target)

        if ok then look = properties end
    end

    clear()
    SetNuiFocus(false, false)

    finishJob(look)
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end

    clear()

    finishJob(nil)
end)

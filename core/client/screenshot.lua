
local RESOURCE = GetCurrentResourceName()

local MAX_BODY = 4 * 1024 * 1024
local UPLOAD_RATE = 1000000 -- bytes a second for the latent upload
local STEP_TIMEOUT = 15000

-- The cut-out takes the same moment twice, once in front of each backdrop.
-- The two colours are equally bright, so the game's exposure does not move
-- between them. gg_lib's own NUI reads the game frame (no screenshot-basic)
-- and works out from the difference how see-through every pixel is: green
-- paint and glass come out right, not keyed away.
local GREEN   = { 0, 170, 0 }
local MAGENTA = { 255, 0, 255 }

local busy = false
local vehicle = nil
local scene = nil -- { at = vector4, colour = { r, g, b } or nil } while a capture runs

local steps = {}
local nextStep = 0
local nextShot = 0
local pendingStorage = {}
local nextStorage = 0

local FALLBACK_SPOT = vector4(-1324.13, -2257.61, 48.77, 260.0)

local function setup()
    local ok, stored = pcall(GGCallback.await, "gg_lib:screenshot:setup")
    local at, greenscreen = FALLBACK_SPOT, true

    if ok and type(stored) == "table" then
        local spot = stored.spot

        if type(spot) == "table" and tonumber(spot.x) then
            at = vector4(spot.x, spot.y, spot.z, tonumber(spot.heading) or 0.0)
        end

        if stored.greenscreen == false then greenscreen = false end
    end

    return at, greenscreen
end

-- Every frame of a capture: no HUD in the picture, and the backdrop around
-- the spot when the cut-out is on.
local function runScene()
    CreateThread(function()
        while scene do
            HideHudAndRadarThisFrame()
            ThefeedHideThisFrame()

            local colour, at = scene.colour, scene.at

            if colour then
                DrawMarker(
                    28,
                    at.x, at.y, at.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    25.0, 25.0, 25.0,
                    colour[1], colour[2], colour[3], 255,
                    false, true, 2, false, nil, nil, false
                )
            end

            Wait(0)
        end
    end)
end

local props = {}

local function fitProps(list)
    if type(list) ~= "table" or not vehicle then return end

    local bone = GetEntityBoneIndexByName(vehicle, "chassis")
    local at = GetEntityCoords(vehicle)

    for _, spec in ipairs(list) do
        local hash = joaat(spec.model)

        if IsModelValid(hash) then
            RequestModel(hash)

            for _ = 1, 300 do
                if HasModelLoaded(hash) then break end
                Wait(10)
            end

            if HasModelLoaded(hash) then
                local prop = CreateObject(hash, at.x, at.y, at.z, false, false, false)
                local offset = spec.offset or {}
                local rotation = spec.rotation or {}

                AttachEntityToEntity(
                    prop, vehicle, bone,
                    tonumber(offset.x) or 0.0, tonumber(offset.y) or 0.0, tonumber(offset.z) or 0.0,
                    tonumber(rotation.x) or 0.0, tonumber(rotation.y) or 0.0, tonumber(rotation.z) or 0.0,
                    true, true, false, false, 2, true
                )

                SetModelAsNoLongerNeeded(hash)
                props[#props + 1] = prop
            end
        end
    end
end

local function despawn()
    for _, prop in ipairs(props) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    props = {}

    if not vehicle then return end

    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
    vehicle = nil
end

local function spawn(model, at)
    local hash = joaat(model)

    if not IsModelValid(hash) then return false end

    RequestModel(hash)

    for _ = 1, 500 do
        if HasModelLoaded(hash) then break end
        Wait(10)
    end

    if not HasModelLoaded(hash) then return false end

    despawn()

    vehicle = CreateVehicle(hash, at.x, at.y, at.z, at.w or 0.0, false, false)
    if not vehicle or vehicle == 0 then return false end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    FreezeEntityPosition(vehicle, true)
    SetModelAsNoLongerNeeded(hash)

    return true
end

local function frameSubject(cam, at)
    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))

    local length = maximum.y - minimum.y
    local width  = maximum.x - minimum.x
    local height = maximum.z - minimum.z

    local scale = math.max(0.6, math.sqrt(math.max(length, width) / 5.0))
    local aim   = at.z + height * 0.5

    SetCamCoord(cam, at.x + 7.0 * scale, at.y + 4.0 * scale, aim + 2.0 * scale)
    PointCamAtCoord(cam, at.x, at.y, aim)
    SetCamFov(cam, 40.0)
end

-- One step of a picture in gg_lib's NUI: "a" keeps the green frame, "b"
-- takes the magenta one and returns the cut-out, "plain" returns the frame
-- as it is. Each waits for the game to actually show its backdrop.
local function nuiStep(step, shot, quality, fit)
    nextStep = nextStep + 1

    local request = tostring(nextStep)
    local waiting = promise.new()

    steps[request] = waiting

    SendNUIMessage({
        action = "gg_screenshot",
        data   = {
            request = request, shot = shot, step = step, quality = quality,
            maxWidth = fit and fit.maxWidth, maxHeight = fit and fit.maxHeight,
        },
    })

    CreateThread(function()
        Wait(STEP_TIMEOUT)

        if steps[request] then
            steps[request] = nil
            waiting:resolve({ ok = false, error = "the picture timed out" })
        end
    end)

    return Citizen.Await(waiting)
end

RegisterNUICallback("gg_screenshot_done", function(data, cb)
    cb("ok")

    local request = type(data) == "table" and data.request and tostring(data.request)
    local waiting = request and steps[request]

    if not waiting then return end

    steps[request] = nil
    waiting:resolve(data)
end)

-- `fit` ({ maxWidth, maxHeight }, either may be nil) scales the finished
-- picture down to fit, keeping its shape.
local function takePicture(greenscreen, quality, fit)
    if not greenscreen then return nuiStep("plain", nil, quality, fit) end

    nextShot = nextShot + 1
    local shot = tostring(nextShot)

    scene.colour = GREEN
    local first = nuiStep("a", shot, quality)
    if not first or not first.ok then return first end

    scene.colour = MAGENTA
    local cutout = nuiStep("b", shot, quality, fit)
    scene.colour = GREEN

    return cutout
end

RegisterNetEvent("gg_lib:screenshot:stored", function(id, location, request, reason)
    local waiting = request and pendingStorage[request]
    if not waiting then return end

    pendingStorage[request] = nil
    waiting:resolve({ location = location, error = reason })
end)

-- One latent event per picture: FiveM splits it up and paces it, so a large
-- image never stalls the connection.
local function sendToServer(id, webpB64, target, folder, storage)
    if #webpB64 > MAX_BODY then
        return { error = "image exceeded the size limit" }
    end

    nextStorage = nextStorage + 1
    local request = tostring(nextStorage)
    local waiting = promise.new()
    pendingStorage[request] = waiting

    TriggerLatentServerEvent("gg_lib:screenshot:upload", UPLOAD_RATE, {
        id      = id,
        request = request,
        body    = webpB64,
        target  = target,
        folder  = folder,
        storage = storage,
    })

    CreateThread(function()
        Wait(30000 + math.ceil(#webpB64 * 1000 / UPLOAD_RATE))

        if pendingStorage[request] then
            pendingStorage[request] = nil
            waiting:resolve({ error = "storage timed out" })
        end
    end)

    return Citizen.Await(waiting)
end

local function capture(entries, options)
    if busy then return false, "a capture is already running" end
    if type(entries) ~= "table" or #entries == 0 then return false, "nothing to capture" end

    busy = true
    options = options or {}

    local target = options.target or RESOURCE
    local folder = options.folder or "vehicle_images"
    local at, greenscreen = setup()

    if type(options.greenscreen) == "boolean" then greenscreen = options.greenscreen end

    local fit = { maxWidth = tonumber(options.maxWidth), maxHeight = tonumber(options.maxHeight) }

    local radarWasVisible = not IsRadarHidden()
    if radarWasVisible then DisplayRadar(false) end

    SetFocusPosAndVel(at.x, at.y, at.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(at.x, at.y, at.z)

    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    RenderScriptCams(true, false, 0, true, false)

    scene = { at = at, colour = greenscreen and GREEN or nil }
    runScene()

    local done, failed, stored = {}, {}, {}
    local stopped = false

    local ok, err = pcall(function()
        for index, entry in ipairs(entries) do
            -- The only place this can be called off. Whoever is watching says
            -- no by answering false, and it takes effect before the next car
            -- is spawned rather than half way through the one in hand.
            if options.progress and options.progress(index, #entries, entry) == false then
                stopped = true
                break
            end

            if not spawn(entry.vehicle, at) then
                failed[#failed + 1] = { id = entry.id, error = "model would not load" }
                goto continue
            end

            if entry.mods then
                pcall(GGVehicle.setProperties, vehicle, entry.mods)
            end

            local paint = entry.color

            if type(paint) == "table" and type(paint.primary) == "number" and type(paint.secondary) == "number" then
                SetVehicleColours(vehicle, math.floor(paint.primary), math.floor(paint.secondary))
            elseif type(paint) == "table" and type(paint.primary) == "table" and type(paint.secondary) == "table" then
                SetVehicleCustomPrimaryColour(vehicle, paint.primary.r, paint.primary.g, paint.primary.b)
                SetVehicleCustomSecondaryColour(vehicle, paint.secondary.r, paint.secondary.g, paint.secondary.b)
            end

            fitProps(entry.props)

            TriggerEvent("gg_lib:screenshot:subject", vehicle, entry.id)

            frameSubject(cam, at)

            Wait(options.settle or 1200)

            local picture = takePicture(greenscreen, options.quality, fit)

            if not picture or not picture.ok or type(picture.webpB64) ~= "string" then
                failed[#failed + 1] = { id = entry.id, error = (picture and picture.error) or "the picture failed" }
                goto continue
            end

            local saved = sendToServer(tostring(entry.id), picture.webpB64, target, folder, options.storage)
            if not saved or not saved.location then
                failed[#failed + 1] = { id = entry.id, error = (saved and saved.error) or "storage failed" }
                goto continue
            end

            done[#done + 1] = entry.id
            stored[entry.id] = saved.location

            ::continue::
        end
    end)

    scene = nil
    despawn()

    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(cam, false)
    ClearFocus()

    if radarWasVisible then DisplayRadar(true) end

    busy = false

    if not ok then return false, tostring(err) end

    return true, { captured = done, failed = failed, stored = stored, stopped = stopped }
end

exports("ggCaptureVehicles", function(entries, options)
    return capture(entries, options)
end)

RegisterNetEvent("gg_lib:screenshot:run", function(entries, options)
    capture(entries, options)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= RESOURCE then return end

    scene = nil
    despawn()

    RenderScriptCams(false, false, 0, true, false)
    ClearFocus()
end)

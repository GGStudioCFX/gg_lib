
local RESOURCE = GetCurrentResourceName()

local CHUNK_SIZE = 8192
local MAX_BODY = 4 * 1024 * 1024
local MAX_CHUNKS = 512

local busy = false
local vehicle = nil
local backdrop = false

local pending = {}
local nextRequest = 0
local pendingStorage = {}
local nextStorage = 0

local FALLBACK_SPOT = vector4(-1324.13, -2257.61, 48.77, 260.0)

local function spot()
    local ok, stored = pcall(GGCallback.await, "gg_lib:screenshot:spot")

    if ok and type(stored) == "table" and tonumber(stored.x) then
        return vector4(stored.x, stored.y, stored.z, tonumber(stored.heading) or 0.0)
    end

    return FALLBACK_SPOT
end

local function drawBackdrop(at)
    CreateThread(function()
        while backdrop do
            Wait(0)

            DrawMarker(
                28,
                at.x, at.y, at.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                25.0, 25.0, 25.0,
                0, 255, 0, 255,
                false, true, 2, false, nil, nil, false
            )
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

local function processImage(image, quality)
    nextRequest = nextRequest + 1

    local id = tostring(nextRequest)
    local promise = promise.new()

    pending[id] = promise

    SendNUIMessage({
        action = "gg_screenshot_process",
        data   = { id = id, image = image, quality = quality },
    })

    CreateThread(function()
        Wait(15000)

        if pending[id] then
            pending[id] = nil
            promise:resolve({ ok = false, error = "timed out" })
        end
    end)

    return Citizen.Await(promise)
end

RegisterNUICallback("gg_screenshot_done", function(data, cb)
    cb("ok")

    local id = data and tostring(data.id)
    local promise = id and pending[id]

    if not promise then return end

    pending[id] = nil
    promise:resolve(data)
end)

RegisterNetEvent("gg_lib:screenshot:stored", function(id, location, request, reason)
    local waiting = request and pendingStorage[request]
    if not waiting then return end

    pendingStorage[request] = nil
    waiting:resolve({ location = location, error = reason })
end)

local function sendToServer(id, webpB64, target, folder, storage)
    local total = math.ceil(#webpB64 / CHUNK_SIZE)
    if total < 1 or total > MAX_CHUNKS or #webpB64 > MAX_BODY then
        return { error = "image exceeded the size limit" }
    end

    nextStorage = nextStorage + 1
    local request = tostring(nextStorage)
    local waiting = promise.new()
    pendingStorage[request] = waiting

    for index = 1, total do
        local from = (index - 1) * CHUNK_SIZE + 1
        local to   = math.min(index * CHUNK_SIZE, #webpB64)

        TriggerServerEvent("gg_lib:screenshot:chunk", {
            id     = id,
            index  = index,
            total  = total,
            body   = webpB64:sub(from, to),
            request = request,
            target = target,
            folder = folder,
            storage = storage,
        })

        Wait(10)
    end

    CreateThread(function()
        Wait(30000)
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

    if GetResourceState("screenshot-basic") ~= "started" then
        return false, "screenshot-basic is not started"
    end

    options = options or {}

    local target = options.target or RESOURCE
    local folder = options.folder or "vehicle_images"
    local at     = spot()

    busy = true

    local radarWasVisible = not IsRadarHidden()
    if radarWasVisible then DisplayRadar(false) end

    SetFocusPosAndVel(at.x, at.y, at.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(at.x, at.y, at.z)

    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    RenderScriptCams(true, false, 0, true, false)

    backdrop = true
    drawBackdrop(at)

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

            local shot = promise.new()

            exports["screenshot-basic"]:requestScreenshot(function(image)
                shot:resolve(image)
            end)

            local image = Citizen.Await(shot)

            if not image then
                failed[#failed + 1] = { id = entry.id, error = "capture returned nothing" }
                goto continue
            end

            local processed = processImage(image, options.quality)

            if not processed or not processed.ok or not processed.webpB64 then
                failed[#failed + 1] = { id = entry.id, error = (processed and processed.error) or "processing failed" }
                goto continue
            end

            local saved = sendToServer(tostring(entry.id), processed.webpB64, target, folder, options.storage)
            if not saved or not saved.location then
                failed[#failed + 1] = { id = entry.id, error = (saved and saved.error) or "storage failed" }
                goto continue
            end

            done[#done + 1] = entry.id
            stored[entry.id] = saved.location

            ::continue::
        end
    end)

    backdrop = false
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

    backdrop = false
    despawn()

    RenderScriptCams(false, false, 0, true, false)
    ClearFocus()
end)

gg.camera = gg.camera or {}

local camera = nil
gg.camera.createCameraNPC = function(entity, offset)
    local offset = offset or {0.0,0.0,0.0}

    SetPedTalk(entity)
    PlayAmbientSpeech1(entity, 'GENERIC_HI', 'SPEECH_PARAMS_STANDARD')

    if not DoesEntityExist(entity) then
        print("Entity does not exist.")
        return
    end

    local coords = GetOffsetFromEntityInWorldCoords(entity, offset[1], 1.35 + offset[1], 0.75 + offset[1])
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    SetCamCoord(cam, coords.x, coords.y, coords.z)
    SetCamRot(cam, 0.0, 0.0, GetEntityHeading(entity) - 180, 0)
    SetCamFov(cam, 60.0)
    camera = cam
end

gg.camera.createCameraCoord = function(coord, offset, rotation)
    if not coord or type(coord) ~= "table" then return end

    local offset = offset or {0.0, 0.0, 0.0}
    local rotation = rotation or {0.0, 0.0, 0.0}

    local heading = coord[4] or 0.0
    local hRad = math.rad(heading)
    local ox, oy = offset[1] or 0.0, offset[2] or 0.0
    local rx = ox * math.cos(hRad) - oy * math.sin(hRad)
    local ry = ox * math.sin(hRad) + oy * math.cos(hRad)

    local camX = coord[1] + rx
    local camY = coord[2] + ry
    local camZ = coord[3] + (offset[3] or 0.0)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, camX, camY, camZ)
    SetCamRot(cam, rotation[1], rotation[2], rotation[3], 2)
    SetCamFov(cam, 60.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)

    camera = cam
end

gg.camera.removeCamera = function()
    if camera then
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        local playerPed = PlayerPedId()
        local coords = GetGameplayCamCoord()
        local rot = GetGameplayCamRot(2)

        SetCamCoord(cam, coords.x, coords.y, coords.z)
        SetCamRot(cam, rot.x, rot.y, rot.z, 2)
        SetCamFov(cam, GetGameplayCamFov())
        SetCamActive(cam, true)

        SetCamActiveWithInterp(cam, camera, 800, 1, 1) -- smooth transition
        Wait(800)

        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(camera, true)
        DestroyCam(cam, true)
        camera = nil
    end
end

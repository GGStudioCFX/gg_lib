
local RESOURCE = GetCurrentResourceName()

local LOAD_TIMEOUT_MS = 5000

local anim = { dict = "", clip = "", playing = false }

local function stopAnim()
    local ped = PlayerPedId()

    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)

    anim.playing = false

    SendNUIMessage({ action = "anim_state", data = { PLAYING = false } })
end

local function flagsFrom(options)
    local flags = 0

    if options.loop then flags = flags + 1 end
    if options.hold then flags = flags + 2 end
    if options.upper then flags = flags + 16 end
    if options.move then flags = flags + 32 end

    return flags
end

RegisterNUICallback("media_open", function(data, cb)
    cb({ ok = true })

    GG_VIEWER.open(type(data) == "table" and data.name or "media")
end)

RegisterNUICallback("media_close", function(_, cb)
    cb({ ok = true })

    GG_VIEWER.close()
end)

RegisterNUICallback("anim_play", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.dict) ~= "string" or type(data.clip) ~= "string" then return end

    CreateThread(function()
        RequestAnimDict(data.dict)

        local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

        while not HasAnimDictLoaded(data.dict) do
            if GetGameTimer() > deadline then
                SendNUIMessage({ action = "anim_state", data = { PLAYING = false, ERROR = data.dict } })

                return
            end

            Wait(0)
        end

        anim.dict, anim.clip, anim.playing = data.dict, data.clip, true

        TaskPlayAnim(
            PlayerPedId(), data.dict, data.clip,
            tonumber(data.blendIn) or 8.0, tonumber(data.blendOut) or -8.0,
            tonumber(data.duration) or -1,
            flagsFrom(data), 0.0, false, false, false
        )

        RemoveAnimDict(data.dict)

        SendNUIMessage({ action = "anim_state", data = { PLAYING = true, DICT = data.dict, CLIP = data.clip } })
    end)
end)

RegisterNUICallback("anim_stop", function(_, cb)
    cb({ ok = true })

    stopAnim()
end)

local sound = { id = nil, box = nil }

local BOX_MODEL = "prop_boombox_01"

local function silence()
    if not sound.id then return end

    StopSound(sound.id)
    ReleaseSoundId(sound.id)

    sound.id = nil
end

local function clearBox()
    if sound.box and DoesEntityExist(sound.box) then DeleteEntity(sound.box) end

    sound.box = nil
end

local function boxOut()
    if sound.box and DoesEntityExist(sound.box) then return sound.box end

    local hash = joaat(BOX_MODEL)

    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_TIMEOUT_MS

    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    local ped = PlayerPedId()
    local at  = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)

    local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, at.z + 1.0, false)

    sound.box = CreateObject(hash, at.x, at.y, (found and groundZ or at.z) + 0.02, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(sound.box) then
        sound.box = nil

        return nil
    end

    PlaceObjectOnGroundProperly(sound.box)
    FreezeEntityPosition(sound.box, true)
    SetEntityHeading(sound.box, GetEntityHeading(ped) + 180.0)

    return sound.box
end

RegisterNUICallback("sound_play", function(data, cb)
    cb({ ok = true })

    if type(data) ~= "table" or type(data.name) ~= "string" or data.name == "" then return end

    local set = type(data.set) == "string" and data.set ~= "" and data.set or nil

    CreateThread(function()
        silence()

        sound.id = GetSoundId()

        if data.frontend == false then
            local box = boxOut()

            if not box then
                SendNUIMessage({ action = "sound_state", data = { ERROR = BOX_MODEL } })

                return
            end

            PlaySoundFromEntity(sound.id, data.name, box, set, false, 0)
        else
            clearBox()

            PlaySoundFrontend(sound.id, data.name, set, false)
        end
    end)
end)

RegisterNUICallback("sound_bank", function(data, cb)
    if type(data) ~= "table" or type(data.name) ~= "string" or data.name == "" then
        cb({ ok = false })

        return
    end

    if data.release then
        ReleaseNamedScriptAudioBank(data.name)

        cb({ ok = true, loaded = false })

        return
    end

    local deadline = GetGameTimer() + 2000
    local ok = false

    while GetGameTimer() < deadline do
        ok = RequestScriptAudioBank(data.name, false)

        if ok then break end

        Wait(0)
    end

    cb({ ok = true, loaded = ok == true })
end)

RegisterNUICallback("sound_stop", function(_, cb)
    cb({ ok = true })

    silence()
    clearBox()
end)

RegisterNetEvent("gg_lib:sound:heard", function(netId, name, set)
    if type(name) ~= "string" or name == "" then return end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end

    local ped = NetToPed(netId)

    if not (ped and DoesEntityExist(ped)) then return end

    if ped == PlayerPedId() then return end

    local id = GetSoundId()

    PlaySoundFromEntity(id, name, ped, type(set) == "string" and set ~= "" and set or nil, false, 0)

    SetTimeout(6000, function() ReleaseSoundId(id) end)
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= RESOURCE then return end

    if anim.playing then stopAnim() end

    silence()
    clearBox()
end)

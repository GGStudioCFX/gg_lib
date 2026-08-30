gg.sound = gg.sound or {}

function gg.sound.play(name, set)
    if type(name) ~= "string" or name == "" then return false end

    PlaySoundFrontend(-1, name, type(set) == "string" and set ~= "" and set or nil, false)

    return true
end

function gg.sound.shout(name, set, range)
    if type(name) ~= "string" or name == "" then return false end

    local ped = PlayerPedId()
    local id  = GetSoundId()

    PlaySoundFromEntity(id, name, ped, type(set) == "string" and set ~= "" and set or nil, false, 0)

    SetTimeout(6000, function() ReleaseSoundId(id) end)

    TriggerServerEvent("gg_lib:sound:shout", name, set, range)

    return true
end

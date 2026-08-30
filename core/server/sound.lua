
local DEFAULT_RANGE = 12.0
local MAX_RANGE     = 60.0

local THROTTLE_MS = 120

local lastAt = {}

local function allowed(source)
    local now  = GetGameTimer()
    local last = lastAt[source] or 0

    if (now - last) < THROTTLE_MS then return false end

    lastAt[source] = now

    return true
end

RegisterNetEvent("gg_lib:sound:shout", function(name, set, range)
    local source = source

    if type(name) ~= "string" or name == "" then return end
    if not allowed(source) then return end

    local from = GetEntityCoords(GetPlayerPed(source))

    if not from then return end

    range = math.min(tonumber(range) or DEFAULT_RANGE, MAX_RANGE)

    local netId = NetworkGetNetworkIdFromEntity(GetPlayerPed(source))

    if netId == 0 then return end

    local heard = {}

    for _, player in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(player)

        if ped and ped ~= 0 then
            local at = GetEntityCoords(ped)

            if at and #(from - at) <= range then heard[#heard + 1] = player end
        end
    end

    for index = 1, #heard do
        TriggerClientEvent("gg_lib:sound:heard", heard[index], netId, name, set)
    end
end)

AddEventHandler("playerDropped", function()
    lastAt[source] = nil
end)

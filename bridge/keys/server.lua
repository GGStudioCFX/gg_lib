--------------------------------------------------
-- MARK: Server-given keys
--------------------------------------------------

-- Some key scripts only honor a key request made beside the car, and a depot
-- hands its keys over at a desk. Those keys are given from here instead, and
-- only for a car this resource spawned, so a client cannot name any car on the
-- server and walk off with it.
local GRANT = GetCurrentResourceName() .. ":gg_keys"

-- One row per key script the client may ask for (bridge/keys/client.lua viaServer).
local grants = {
    -- JG's entity exports return true when something changed and nil when the
    -- key was already held, the car is excluded or it failed.
    ["jg-vehiclekeys"] = {
        give = function(source, veh)
            if exports["jg-vehiclekeys"]:giveKeysToEntity(source, veh, true) then return true end

            return exports["jg-vehiclekeys"]:hasKeysForEntity(source, veh) == true
        end,
        remove = function(source, veh)
            exports["jg-vehiclekeys"]:removeKeysFromEntity(source, veh, true)
        end,
    },

    ["qbx_vehiclekeys"] = {
        give = function(source, veh)
            if exports.qbx_vehiclekeys:GiveKeys(source, veh, true) then return true end

            -- Nothing given because the key was already held.
            return exports.qbx_vehiclekeys:HasKeys(source, veh) == true
        end,
        remove = function(source, veh)
            exports.qbx_vehiclekeys:RemoveKeys(source, veh, true)
        end,
    },
}

local function answer(source, action, netid, keys)
    local grant = grants[keys]

    if not grant or GetResourceState(keys) ~= "started" then return false end
    if type(netid) ~= "number" then return false end

    local veh = NetworkGetEntityFromNetworkId(netid)

    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return false end

    -- Giving up your own key needs no proof.
    if action == "remove" then
        local ok = pcall(grant.remove, source, veh)

        return ok
    end

    if action ~= "add" or not gg.vehicleManager.spawnedHere(veh) then return false end

    local ok, given = pcall(grant.give, source, veh)

    return ok and given == true
end

-- Detection can run again when a key script starts late; the answer is
-- registered once and checks what is running each time it is asked.
return function()
    if rawget(gg, "__keys_grant") then return true end

    rawset(gg, "__keys_grant", true)

    gg.callback.register(GRANT, answer)

    return true
end

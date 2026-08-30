gg.pedManager = gg.pedManager or {}

local activePeds = {}
local pedCounter = 1

gg.pedManager.spawnPed = function(data, network)
    local networked = network or false
    if data.model then
        local model = data.model
        gg.util.loadModel(model)

        if IsModelAPed(model) then
            local pedLabel = data.label or ("ped_" .. pedCounter)
            if not activePeds[pedLabel] then
                activePeds[pedLabel] = CreatePed(
                    4,
                    model,
                    data.coords.x,
                    data.coords.y,
                    data.coords.z - 1.03,
                    data.coords.w,
                    networked,
                    true
                )
            end

            if activePeds[pedLabel] then
                local ped = gg.cleanup.track(activePeds[pedLabel])
                SetEntityHeading(ped, data.coords.w)
                TaskStartScenarioInPlace(ped, data.pedScene, 0, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetPedCanRagdoll(ped, false)
                SetPedConfigFlag(ped, 32, false)
                SetPedConfigFlag(ped, 33, false)
                SetPedConfigFlag(ped, 104, true)
                SetPedCanBeTargetted(ped, false)
                SetPedSuffersCriticalHits(ped, false)
                pedCounter = pedCounter + 1
                return ped
            end
        end
    end
    return nil
end

gg.pedManager.deletePed = function(label)
    if activePeds[label] then
        gg.cleanup.forget(activePeds[label])

        DeleteEntity(activePeds[label])
        activePeds[label] = nil
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for k in pairs(activePeds) do
        gg.pedManager.deletePed(k)
    end
end)

gg.cleanup.job(function()
    activePeds = {}
end)

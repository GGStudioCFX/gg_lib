gg.cleanup = gg.cleanup or {}

local KINDS = { entity = true, blip = true, cam = true, dui = true, particle = true }

local tracked = { entity = {}, blip = {}, cam = {}, dui = {}, particle = {} }
local jobs = {}

local function killEntity(handle)
    if not DoesEntityExist(handle) then return end

    if NetworkGetEntityIsNetworked(handle) then
        NetworkRequestControlOfEntity(handle)
    end

    SetEntityAsMissionEntity(handle, true, true)
    DeleteEntity(handle)
end

local function killBlip(handle)
    if DoesBlipExist(handle) then RemoveBlip(handle) end
end

local function killCam(handle)
    if DoesCamExist(handle) then DestroyCam(handle, false) end
end

local function killDui(handle)
    pcall(DestroyDui, handle)
end

local function killParticle(handle)
    if DoesParticleFxLoopedExist(handle) then StopParticleFxLooped(handle, false) end
end

local KILL = {
    entity   = killEntity,
    blip     = killBlip,
    cam      = killCam,
    dui      = killDui,
    particle = killParticle,
}

function gg.cleanup.track(handle, kind)
    kind = KINDS[kind] and kind or "entity"

    if type(handle) ~= "number" or handle == 0 then return handle end

    tracked[kind][handle] = true

    return handle
end

function gg.cleanup.forget(handle, kind)
    if type(handle) ~= "number" then return end

    if kind and KINDS[kind] then
        tracked[kind][handle] = nil

        return
    end

    for name in pairs(tracked) do tracked[name][handle] = nil end
end

function gg.cleanup.job(fn)
    if type(fn) ~= "function" then return end

    jobs[#jobs + 1] = fn
end

function gg.cleanup.count()
    local out, total = {}, 0

    for kind, list in pairs(tracked) do
        local count = 0

        for _ in pairs(list) do count = count + 1 end

        out[kind] = count
        total = total + count
    end

    out.jobs = #jobs
    out.total = total

    return out
end

function gg.cleanup.now()
    for index = 1, #jobs do pcall(jobs[index]) end

    jobs = {}

    for _, kind in ipairs({ "blip", "particle", "dui", "cam", "entity" }) do
        for handle in pairs(tracked[kind]) do pcall(KILL[kind], handle) end

        tracked[kind] = {}
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    gg.cleanup.now()
end)

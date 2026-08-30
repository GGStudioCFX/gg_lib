gg.cleanup = gg.cleanup or {}

local entities = {}
local jobs = {}

function gg.cleanup.track(handle)
    if type(handle) ~= "number" or handle == 0 then return handle end

    entities[handle] = true

    return handle
end

function gg.cleanup.forget(handle)
    if type(handle) ~= "number" then return end

    entities[handle] = nil
end

function gg.cleanup.job(fn)
    if type(fn) ~= "function" then return end

    jobs[#jobs + 1] = fn
end

function gg.cleanup.count()
    local total = 0

    for _ in pairs(entities) do total = total + 1 end

    return { entity = total, jobs = #jobs, total = total }
end

function gg.cleanup.now()
    for index = 1, #jobs do pcall(jobs[index]) end

    jobs = {}

    for handle in pairs(entities) do
        if DoesEntityExist(handle) then pcall(DeleteEntity, handle) end
    end

    entities = {}
end

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    gg.cleanup.now()
end)

gg.attach = gg.attach or {}

local RESOURCE = GetCurrentResourceName()

local waiting = {}
local accepted = {}
local sequence = 0

AddEventHandler("gg_lib:attach:placeAccepted", function(resource, id)
    if resource ~= RESOURCE then return end

    accepted[id] = true
end)

AddEventHandler("gg_lib:attach:placeResult", function(resource, id, result)
    if resource ~= RESOURCE then return end

    local answer = waiting[id]
    if not answer then return end

    waiting[id] = nil
    accepted[id] = nil

    answer:resolve(result)
end)

function gg.attach.placeVehicleProps(options)
    if type(options) ~= "table" then return "nothing to place" end

    sequence = sequence + 1

    local id = sequence
    local answer = promise.new()

    waiting[id] = answer

    TriggerEvent("gg_lib:attach:place", RESOURCE, id, options)

    SetTimeout(3000, function()
        if not waiting[id] or accepted[id] then return end

        waiting[id] = nil

        answer:resolve("Restart gg_lib -- its placement editor did not answer")
    end)

    SetTimeout(900000, function()
        if not waiting[id] then return end

        waiting[id] = nil
        accepted[id] = nil

        answer:resolve(nil)
    end)

    return Citizen.Await(answer)
end

function gg.attach.editor()
    return exports.gg_lib:ggAttachEditor()
end

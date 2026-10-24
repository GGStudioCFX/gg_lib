gg.placement = gg.placement or {}

local RESOURCE = GetCurrentResourceName()

local waiting = {}
local accepted = {}
local sequence = 0

AddEventHandler("gg_lib:placement:placeAccepted", function(resource, id)
    if resource ~= RESOURCE then return end

    accepted[id] = true
end)

AddEventHandler("gg_lib:placement:placeResult", function(resource, id, result)
    if resource ~= RESOURCE then return end

    local answer = waiting[id]
    if not answer then return end

    waiting[id] = nil
    accepted[id] = nil

    answer:resolve(result)
end)

-- Opens the placement tool with a preview of `options.model` and waits for the player.
-- options: model, title?, placeLabel?, heading?, maxDistance? (metres from the player, default 3),
-- tint? (the preview's texture variation), with? (more models set down on the same origin)
-- Returns { x, y, z, heading } for the object's position when placed, nil when cancelled,
-- or a string explaining why the tool could not open.
function gg.placement.placeObject(options)
    if type(options) ~= "table" or options.model == nil then return "nothing to place" end

    sequence = sequence + 1

    local id = sequence
    local answer = promise.new()

    waiting[id] = answer

    TriggerEvent("gg_lib:placement:place", RESOURCE, id, options)

    SetTimeout(3000, function()
        if not waiting[id] or accepted[id] then return end

        waiting[id] = nil

        answer:resolve("Restart gg_lib -- its placement tool did not answer")
    end)

    SetTimeout(330000, function()
        if not waiting[id] then return end

        waiting[id] = nil
        accepted[id] = nil

        answer:resolve(nil)
    end)

    return Citizen.Await(answer)
end

-- Closes a placement this resource opened, as if the player cancelled it.
function gg.placement.cancel()
    TriggerEvent("gg_lib:placement:cancel", RESOURCE)
end

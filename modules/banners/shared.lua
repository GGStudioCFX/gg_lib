gg.banners = gg.banners or {}

local SHAPES = {
    ["gg_taxiprop_bannerdui"]      = "gg_taxiprop_bannerdui_%d",
    ["gg_taxiprop_bannerdui_flat"] = "gg_taxiprop_bannerdui_flat_%d",
}

local TARGET = "ggtaxibanner"

local SLOTS = 6

local byModel = {}

for shape, pattern in pairs(SHAPES) do
    byModel[GetHashKey(shape)] = 1

    for slot = 2, SLOTS do
        byModel[GetHashKey(pattern:format(slot))] = slot
    end
end

function gg.banners.slots()
    return SLOTS
end

function gg.banners.model(shape, slot)
    local pattern = SHAPES[shape]
    if not pattern then return shape end

    slot = tonumber(slot) or 1

    if slot <= 1 or slot > SLOTS then return shape end

    return pattern:format(slot)
end

function gg.banners.target(slot)
    slot = tonumber(slot) or 1

    if slot <= 1 then return TARGET end

    return ("%s_%d"):format(TARGET, slot)
end

function gg.banners.slotOf(model)
    return byModel[model]
end

function gg.banners.isBoard(model)
    return byModel[model] ~= nil
end

function gg.banners.isShape(name)
    return SHAPES[name] ~= nil
end

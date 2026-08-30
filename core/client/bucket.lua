
GG_EDITOR_BUCKET = GG_EDITOR_BUCKET or { active = false }

function GG_EDITOR_BUCKET.enter()
    if GG_EDITOR_BUCKET.active then return true end

    local ok = pcall(function()
        return GGCallback.await("gg_lib:editor:bucketEnter")
    end)

    GG_EDITOR_BUCKET.active = ok == true

    return GG_EDITOR_BUCKET.active
end

function GG_EDITOR_BUCKET.leave()
    if not GG_EDITOR_BUCKET.active then return end

    GG_EDITOR_BUCKET.active = false

    pcall(function()
        GGCallback.await("gg_lib:editor:bucketLeave")
    end)
end

RegisterNetEvent("gg_lib:editor:forceExit", function()
    GG_EDITOR_BUCKET.active = false
end)

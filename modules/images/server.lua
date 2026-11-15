gg.images = gg.images or {}

function gg.images.save(owner, name, base64, mime)
    return exports.gg_lib:ggImageSave(owner, name, base64, mime)
end

function gg.images.delete(owner, name)
    return exports.gg_lib:ggImageDelete(owner, name)
end

function gg.images.versions(owner)
    return exports.gg_lib:ggImageVersions(owner)
end

function gg.images.get(owner, name)
    return exports.gg_lib:ggImageGet(owner, name)
end

-- handler(owner, name, version); version is nil when the picture was deleted.
function gg.images.onStored(handler)
    return AddEventHandler("gg_lib:image:stored", handler)
end

gg.images = gg.images or {}

-- Waits for the pictures, so call it from a thread. Returns
-- { [name] = { data = "data:image/webp;base64,...", version = n } } for every
-- name that has one, and a reason as a second value when it fell short.
function gg.images.fetch(owner, names, timeoutMs)
    return exports.gg_lib:ggImageFetch(owner, names, timeoutMs)
end

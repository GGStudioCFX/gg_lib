gg.screenshot = gg.screenshot or {}

function gg.screenshot.vehicles(entries, options)
    options = options or {}
    options.target = options.target or GetCurrentResourceName()

    return exports.gg_lib:ggCaptureVehicles(entries, options)
end

function gg.screenshot.onStored(handler)
    RegisterNetEvent("gg_lib:screenshot:stored", handler)
end

gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    if type(data) ~= "table" then return end

    local coords = data.coords or GetEntityCoords(PlayerPedId())
    
    exports.tk_dispatch:addCall({
        title = data.message or "Dispatch Alert",
        code = data.code or "10-80",
        priority = data.priority,
        coords = coords,
        message = data.message,
        showLocation = true,
        showGender = false,
        showVehicle = data.vehicle ~= nil,
        showWeapon = false,
        showPlate = data.plate ~= nil,
        platePercentage = data.plate and 100 or 0,
        playSound = true,
        removeTime = data.time or 10000,
        jobs = data.jobs or {"police"},
        blip = {
            sprite = data.blipData and data.blipData.sprite or 1,
            color = data.blipData and data.blipData.color or 3,
            scale = data.blipData and data.blipData.scale or 0.8,
            radius = data.blipData and data.blipData.radius or nil,
            flash = data.blipData and data.blipData.flash or false,
        },
    })
end

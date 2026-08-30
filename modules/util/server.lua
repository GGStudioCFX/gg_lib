gg.util = gg.util or {}

gg.util.getOrdinal = function(num)
    local suffixes = {"th", "st", "nd", "rd"}
    local last_digit = num % 10
    local last_two_digits = num % 100

    if last_two_digits >= 11 and last_two_digits <= 13 then
        return tostring(num) .. "th"
    end

    if last_digit == 1 then
        return tostring(num) .. suffixes[2]  -- "st"
    elseif last_digit == 2 then
        return tostring(num) .. suffixes[3]  -- "nd"
    elseif last_digit == 3 then
        return tostring(num) .. suffixes[4]  -- "rd"
    else
        return tostring(num) .. suffixes[1]  -- "th"
    end
end

gg.util.addFile = function(srcResource, srcDir, fileName, destResource, destDir)
    local src = GetResourcePath(srcResource) .. "/" .. srcDir .. "/" .. fileName
    local dest = GetResourcePath(destResource) .. "/" .. destDir .. "/" .. fileName

    local srcFile = io.open(src, "rb")
    if not srcFile then
        print("^1[ERROR]^7 Could not open source file: " .. src)
        return false
    end

    local data = srcFile:read("*all")
    srcFile:close()

    os.execute("mkdir \"" .. dest:match("(.*/)") .. "\"")

    local destFile = io.open(dest, "wb")
    if not destFile then
        print("^1[ERROR]^7 Could not open destination file: " .. dest)
        return false
    end

    destFile:write(data)
    destFile:close()
    return true
end

gg.util.removeFile = function(resource, dir, fileName)
    local path = GetResourcePath(resource) .. "/" .. dir .. "/" .. fileName

    local file = io.open(path, "r")
    if not file then
        print("^1[ERROR]^7 File does not exist: " .. path)
        return false
    end
    file:close()

    local success, reason = os.remove(path)
    if not success then
        print("^1[ERROR]^7 Could not remove file: " .. path .. " (" .. tostring(reason) .. ")")
        return false
    end

    return true
end

gg.util.copyTable = function(orig)
    local function deepCopy(tbl)
        local copy = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                copy[k] = deepCopy(v)
            else
                copy[k] = v
            end
        end
        return copy
    end
    return deepCopy(orig)
end

local function normalizeVehicleGarageType(vehicleType)
    if type(vehicleType) ~= "string" or vehicleType == "" then
        return "car"
    end

    vehicleType = vehicleType:lower()

    if vehicleType == "boat" or vehicleType == "water" then
        return "water"
    end

    if vehicleType == "air" or vehicleType == "aircraft" or vehicleType == "heli" or vehicleType == "helicopter" or vehicleType == "plane" then
        return "air"
    end

    if vehicleType == "car" or vehicleType == "automobile" or vehicleType == "bike" or vehicleType == "bicycle" or vehicleType == "quadbike" then
        return "car"
    end

    return "car"
end

gg.util.normalizeVehicleGarageType = normalizeVehicleGarageType

gg.util.getDefaultGarageForVehicleMeta = function(meta)
    local vehicleType = normalizeVehicleGarageType(type(meta) == "table" and (meta.vehicleGarageType or meta.vehicleType) or nil)
    local defaultGarage = cfg and cfg.settings and cfg.settings.general and cfg.settings.general.default_garage

    if type(defaultGarage) == "table" then
        return defaultGarage[vehicleType] or defaultGarage.car, vehicleType
    end

    return defaultGarage, vehicleType
end

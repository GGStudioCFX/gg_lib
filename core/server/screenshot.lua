
local RESOURCE = GetCurrentResourceName()

local MAX_BODY = 4 * 1024 * 1024

local DECODE = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for index = 1, #alphabet do DECODE[alphabet:byte(index)] = index - 1 end
end

-- Four characters to three bytes at a time. Padding and anything outside the
-- alphabet is dropped first.
local function decodeBase64(text)
    text = text:gsub("[^%w%+/]", "")

    local out, count = {}, 0
    local length = #text
    local char = string.char

    for index = 1, length - 3, 4 do
        local a, b, c, d = text:byte(index, index + 3)
        local value = DECODE[a] << 18 | DECODE[b] << 12 | DECODE[c] << 6 | DECODE[d]

        count = count + 1
        out[count] = char(value >> 16, (value >> 8) & 255, value & 255)
    end

    local rest = length % 4

    if rest > 1 then
        local a, b, c = text:byte(length - rest + 1, length)
        local value = DECODE[a] << 18 | DECODE[b] << 12 | (c and DECODE[c] or 0) << 6

        count = count + 1
        out[count] = rest == 2 and char(value >> 16) or char(value >> 16, (value >> 8) & 255)
    end

    return table.concat(out)
end

local function safeName(name)
    name = tostring(name or ""):gsub("[^%w%-_]", "")

    return name ~= "" and name or nil
end

local function safeFolder(folder)
    if type(folder) ~= "string" then return nil end
    folder = folder:gsub("\\", "/"):gsub("/+$", "")
    folder = folder:gsub("^web/dist/", "")
    if folder == "" or #folder > 128 or folder:sub(1, 1) == "/" or folder:find("[^%w%-%_/]", 1)
        or folder:find("//", 1, true) then return nil end
    return folder
end

local function saveLocally(target, folder, name, binary)
    local root = GetResourcePath(target)

    if not root or root == "" then
        print(("^3[gg_lib] screenshot: '%s' is not a resource on this server^0"):format(target))
        return nil
    end

    local directory = ("%s/web/dist/%s"):format(root, folder)

    if os.getenv("OS") == "Windows_NT" then
        os.execute(('if not exist "%s" mkdir "%s"'):format(directory:gsub("/", "\\"), directory:gsub("/", "\\")))
    else
        os.execute(('mkdir -p "%s"'):format(directory))
    end

    local path = ("%s/%s.webp"):format(directory, name)
    local file = io.open(path, "wb")

    if not file then
        print(("^3[gg_lib] screenshot: could not write %s^0"):format(path))
        return nil
    end

    file:write(binary)
    file:close()

    return ("%s/%s.webp"):format(folder, name)
end

local function uploadOrSave(storage, key, target, folder, name, base64, source, request)
    local function report(location, reason)
        TriggerClientEvent("gg_lib:screenshot:stored", source, name, location, request, reason)
    end

    local function fallback(reason)
        if reason then print(("^3[gg_lib] screenshot: upload failed (%s), saving locally^0"):format(reason)) end

        local relative = saveLocally(target, folder, name, decodeBase64(base64))
        report(relative, relative and nil or "local write failed")
    end

    if storage == "local" or (storage == "auto" and (not key or key == "" or key == "YOUR_API_KEY")) then
        fallback(nil)
        return
    end

    if not key or key == "" or key == "YOUR_API_KEY" then
        fallback("FiveManage API key is missing")
        return
    end

    PerformHttpRequest("https://api.fivemanage.com/api/v3/file/base64", function(status, body)
        if status and status >= 200 and status < 300 and body then
            local ok, parsed = pcall(json.decode, body)
            local url = ok and parsed and parsed.data and parsed.data.url

            if type(url) == "string" and url:match("^https://") then
                report(url)
                return
            end
        end

        fallback("HTTP " .. tostring(status))
    end, "POST", json.encode({
        base64   = "data:image/webp;base64," .. base64,
        filename = name .. ".webp",
        path     = target .. "/" .. folder,
    }), {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = key,
    })
end

local function refuse(source, name, request, reason)
    TriggerClientEvent("gg_lib:screenshot:stored", source, name, nil, request, reason)
end

-- The whole picture in one latent event (the client paces it).
RegisterNetEvent("gg_lib:screenshot:upload", function(payload)
    local source = source

    if type(payload) ~= "table" then return end

    local name = safeName(payload.id)
    if not name then return end

    local request = safeName(payload.request) or name
    local target = safeName(payload.target) or RESOURCE

    if not Admins.canEdit(source, target) then
        print(("^3[gg_lib] screenshot: blocked upload from %s^0"):format(Admins.actor(source)))
        refuse(source, name, request, "not allowed to save images for " .. target)
        return
    end

    local body = payload.body
    if type(body) ~= "string" then return refuse(source, name, request, "image was empty") end

    if #body > MAX_BODY then
        print(("^3[gg_lib] screenshot: '%s' exceeded the size limit^0"):format(name))
        return refuse(source, name, request, "image exceeded the size limit")
    end

    local comma = body:find(",", 1, true)
    if comma then body = body:sub(comma + 1) end
    if body == "" then return refuse(source, name, request, "image was empty") end

    -- Kept as text in the image store under the target, named by the entry id.
    if payload.storage == "database" then
        local id = tostring(payload.id)
        local version, reason = Images.save(target, id, body, "image/webp")

        if not version then return refuse(source, name, request, reason or "the image store refused the image") end

        TriggerClientEvent("gg_lib:screenshot:stored", source, name, "db:" .. id, request)
        return
    end

    local folder = payload.folder == nil and "vehicle_images" or safeFolder(payload.folder)
    if not folder then
        return refuse(source, name, request, "image folder must be under the resource web root")
    end

    local storage = payload.storage
    if storage ~= "local" and storage ~= "fivemanage" then
        storage = GenericSettings.get("screenshot.storage") or "auto"
    end
    if storage ~= "local" and storage ~= "fivemanage" then storage = "auto" end

    uploadOrSave(storage, GenericSettings.get("screenshot.upload_key"), target, folder, name, body, source, request)
end)

GGCallback.register("gg_lib:screenshot:setup", function()
    return {
        spot        = GenericSettings.get("screenshot.location"),
        greenscreen = GenericSettings.get("screenshot.greenscreen") ~= false,
    }
end)

GGCallback.register("gg_lib:screenshot:spot", function()
    return GenericSettings.get("screenshot.location")
end)

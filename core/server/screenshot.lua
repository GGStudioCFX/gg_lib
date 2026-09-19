
local RESOURCE = GetCurrentResourceName()

local MAX_CHUNKS = 512
local MAX_BODY   = 4 * 1024 * 1024

local incoming = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function decodeBase64(text)
    text = text:gsub("[^A-Za-z0-9+/=]", "")

    return (text:gsub(".", function(char)
        local index = ALPHABET:find(char)
        if not index then return "" end

        local value, bits = index - 1, ""
        for position = 6, 1, -1 do
            bits = bits .. (value % 2 ^ position - value % 2 ^ (position - 1) > 0 and "1" or "0")
        end

        return bits
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(bits)
        if #bits ~= 8 then return "" end

        local byte = 0
        for position = 1, 8 do
            byte = byte + (bits:sub(position, position) == "1" and 2 ^ (8 - position) or 0)
        end

        return string.char(byte)
    end))
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

RegisterNetEvent("gg_lib:screenshot:chunk", function(payload)
    local source = source

    if type(payload) ~= "table" then return end

    local name  = safeName(payload.id)
    local request = safeName(payload.request) or name
    local index = tonumber(payload.index)
    local total = tonumber(payload.total)

    if not name or not index or not total then return end
    if total < 1 or total > MAX_CHUNKS or index < 1 or index > total then return end
    if type(payload.body) ~= "string" then return end

    local target = safeName(payload.target) or RESOURCE

    if not Admins.canEdit(source, target) then
        print(("^3[gg_lib] screenshot: blocked upload from %s^0"):format(Admins.actor(source)))
        return
    end

    local key = ("%s:%s"):format(source, request)
    local job = incoming[key]

    if index == 1 then
        job = { parts = {}, size = 0, total = total }
        incoming[key] = job
    end

    if not job or job.blocked or job.total ~= total then return end

    job.size = job.size + #payload.body

    if job.size > MAX_BODY then
        incoming[key] = { blocked = true }
        print(("^3[gg_lib] screenshot: '%s' exceeded the size limit^0"):format(name))
        TriggerClientEvent("gg_lib:screenshot:stored", source, name, nil, request, "image exceeded the size limit")
        return
    end
    job.parts[index] = payload.body

    if index ~= total then return end

    incoming[key] = nil

    for part = 1, total do
        if type(job.parts[part]) ~= "string" then
            TriggerClientEvent("gg_lib:screenshot:stored", source, name, nil, request, "image transfer was incomplete")
            return
        end
    end

    local joined = table.concat(job.parts)
    local comma  = joined:find(",", 1, true)
    local body   = comma and joined:sub(comma + 1) or joined

    if body == "" then
        TriggerClientEvent("gg_lib:screenshot:stored", source, name, nil, request, "image was empty")
        return
    end

    local folder = payload.folder == nil and "vehicle_images" or safeFolder(payload.folder)
    if not folder then
        TriggerClientEvent("gg_lib:screenshot:stored", source, name, nil, request, "image folder must be under the resource web root")
        return
    end

    local storage = payload.storage
    if storage ~= "local" and storage ~= "fivemanage" then
        storage = GenericSettings.get("screenshot.storage") or "auto"
    end
    if storage ~= "local" and storage ~= "fivemanage" then storage = "auto" end

    uploadOrSave(storage, GenericSettings.get("screenshot.upload_key"), target, folder, name, body, source, request)
end)

GGCallback.register("gg_lib:screenshot:spot", function()
    return GenericSettings.get("screenshot.location")
end)

AddEventHandler("playerDropped", function()
    local dropped = tostring(source)

    for key in pairs(incoming) do
        if key:sub(1, #dropped + 1) == dropped .. ":" then incoming[key] = nil end
    end
end)

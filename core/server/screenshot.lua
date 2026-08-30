
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

local function encodeBase64(data)
    return ((data:gsub(".", function(char)
        local byte, bits = string.byte(char), ""
        for position = 8, 1, -1 do
            bits = bits .. (byte % 2 ^ position - byte % 2 ^ (position - 1) > 0 and "1" or "0")
        end

        return bits
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(bits)
        if #bits < 6 then return "" end

        local index = 0
        for position = 1, 6 do
            index = index + (bits:sub(position, position) == "1" and 2 ^ (6 - position) or 0)
        end

        return ALPHABET:sub(index + 1, index + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function safeName(name)
    name = tostring(name or ""):gsub("[^%w%-_]", "")

    return name ~= "" and name or nil
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

local function uploadOrSave(key, target, folder, name, binary, source)
    local function fallback(reason)
        if reason then print(("^3[gg_lib] screenshot: upload failed (%s), saving locally^0"):format(reason)) end

        local relative = saveLocally(target, folder, name, binary)
        TriggerClientEvent("gg_lib:screenshot:stored", source, name, relative)
    end

    if not key or key == "" then
        fallback(nil)
        return
    end

    PerformHttpRequest("https://api.fivemanage.com/api/v3/file/base64", function(status, body)
        if status and status >= 200 and status < 300 and body then
            local ok, parsed = pcall(json.decode, body)
            local url = ok and parsed and parsed.data and parsed.data.url

            if url then
                TriggerClientEvent("gg_lib:screenshot:stored", source, name, url)
                return
            end
        end

        fallback("HTTP " .. tostring(status))
    end, "POST", json.encode({
        base64   = "data:image/webp;base64," .. encodeBase64(binary),
        filename = name .. ".webp",
    }), {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = key,
    })
end

RegisterNetEvent("gg_lib:screenshot:chunk", function(payload)
    local source = source

    if type(payload) ~= "table" then return end

    local name  = safeName(payload.id)
    local index = tonumber(payload.index)
    local total = tonumber(payload.total)

    if not name or not index or not total then return end
    if total < 1 or total > MAX_CHUNKS or index < 1 or index > total then return end
    if type(payload.body) ~= "string" then return end

    if not Admins.canEdit(source) then
        print(("^3[gg_lib] screenshot: blocked upload from %s^0"):format(Admins.actor(source)))
        return
    end

    local key = ("%s:%s"):format(source, name)
    local job = incoming[key]

    if index == 1 or not job then
        job = { parts = {}, size = 0, total = total }
        incoming[key] = job
    end

    job.size = job.size + #payload.body

    if job.size > MAX_BODY then
        job.parts = {}
        print(("^3[gg_lib] screenshot: '%s' exceeded the size limit^0"):format(name))
        return
    end
    job.parts[index] = payload.body

    if index ~= total then return end

    incoming[key] = nil

    local joined = table.concat(job.parts)
    local comma  = joined:find(",", 1, true)
    local body   = comma and joined:sub(comma + 1) or joined

    local target = safeName((payload.target or ""):gsub("[^%w%-_]", "")) or RESOURCE
    local folder = safeName(payload.folder) or "vehicle_images"

    uploadOrSave(GenericSettings.get("screenshot.upload_key"), target, folder, name, decodeBase64(body), source)
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

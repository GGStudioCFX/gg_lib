
Locales = Locales or {}

local FALLBACK = "en"

local loaded = {}
local missing = {}

local function read(code, resource)
    resource = resource or GetCurrentResourceName()
    local cacheKey = resource .. "/" .. code
    if loaded[cacheKey] then return loaded[cacheKey] end
    if missing[cacheKey] then return nil end

    local body = LoadResourceFile(resource, ("locales/%s.json"):format(code))
    local ok, value = pcall(json.decode, body or "")

    if not ok or type(value) ~= "table" then
        missing[cacheKey] = true

        if code ~= FALLBACK and resource == GetCurrentResourceName() then
            print(("^3[gg_lib] locale %s could not be read -- falling back to English^0"):format(code))
        end

        return nil
    end

    loaded[cacheKey] = value

    return value
end

function Locales.code()
    local chosen = GenericSettings and GenericSettings.get("general.language")

    return type(chosen) == "string" and chosen ~= "" and chosen or FALLBACK
end

function Locales.strings(resource)
    local code = Locales.code()
    local out = {}

    local function overlay(rows)
        for key, value in pairs(rows or {}) do
            if type(key) == "string" and type(value) == "string" and value:match("%S") then out[key] = value end
        end
    end

    overlay(read(FALLBACK, resource))
    if code ~= FALLBACK then overlay(read(code, resource)) end

    return next(out) and out or nil
end

function Locales.schema(payload)
    local strings = Locales.strings(payload.generic and GetCurrentResourceName() or payload.resource) or {}
    -- These controls are added to every peer by the shared settings module.
    local shared = Locales.strings() or {}
    for _, prefix in ipairs({ "schema.settings.debug", "schema.groups.developer", "schema.groups.__updates__" }) do
        for _, key in ipairs({ "label", "help" }) do
            local id = prefix .. "." .. key
            strings[id] = strings[id] or shared[id]
        end
    end

    local function metadata(node, prefix)
        local out = {}
        for key, value in pairs(node) do out[key] = value end
        for _, key in ipairs({ "label", "help", "action_help", "suffix" }) do
            out[key] = strings[prefix .. "." .. key] or out[key]
        end
        for _, key in ipairs({ "fields", "item", "options", "row_actions" }) do
            if type(node[key]) == "table" then
                out[key] = {}
                for index, field in ipairs(node[key]) do
                    if type(field) == "table" then
                        local id = field.key or field.id or field.value or index
                        out[key][index] = metadata(field, prefix .. "." .. key .. "." .. tostring(id))
                    else
                        out[key][index] = field
                    end
                end
            end
        end
        return out
    end

    local out = metadata(payload, "schema")
    out.entries, out.groups = {}, {}
    for index, entry in ipairs(payload.entries or {}) do
        out.entries[index] = metadata(entry, "schema." .. entry.path)
    end
    for index, group in ipairs(payload.groups or {}) do
        out.groups[index] = metadata(group, "schema.groups." .. group.id)
    end
    return out
end

function Locales.forget(resource)
    if resource then
        local prefix = resource .. "/"
        for key in pairs(loaded) do
            if key:sub(1, #prefix) == prefix then loaded[key] = nil end
        end
        for key in pairs(missing) do
            if key:sub(1, #prefix) == prefix then missing[key] = nil end
        end
    else
        loaded, missing = {}, {}
    end

    if (not resource or resource == GetCurrentResourceName()) and LocaleNames and LocaleNames.forget then
        LocaleNames.forget()
    end
end

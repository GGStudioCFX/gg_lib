
Locales = Locales or {}

local FALLBACK = "en"

local loaded = {}
local missing = {}

local function read(code)
    if loaded[code] then return loaded[code] end
    if missing[code] then return nil end

    local body = LoadResourceFile(GetCurrentResourceName(), ("locales/%s.json"):format(code))
    local ok, value = pcall(json.decode, body or "")

    if not ok or type(value) ~= "table" then
        missing[code] = true

        if code ~= FALLBACK then
            print(("^3[gg_lib] locale %s could not be read -- falling back to English^0"):format(code))
        end

        return nil
    end

    loaded[code] = value

    return value
end

function Locales.code()
    local chosen = GenericSettings and GenericSettings.get("general.language")

    return type(chosen) == "string" and chosen ~= "" and chosen or FALLBACK
end

function Locales.strings()
    local code = Locales.code()

    if code == FALLBACK then return nil end

    local rows = read(code)

    if not rows then return nil end

    local out = {}

    for key, value in pairs(rows) do
        if type(key) == "string" and type(value) == "string" and value ~= "" then out[key] = value end
    end

    return next(out) and out or nil
end

function Locales.forget()
    loaded, missing = {}, {}

    if LocaleNames and LocaleNames.forget then LocaleNames.forget() end
end

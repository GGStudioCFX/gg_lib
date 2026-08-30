
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

local function count(rows)
    local total = 0

    for _ in pairs(rows or {}) do total = total + 1 end

    return total
end

RegisterCommand("gglocales", function(source)
    if source ~= 0 then return end

    Locales.forget()

    local code = Locales.code()
    local rows = Locales.strings()

    if code == FALLBACK then
        print("[gg_lib] language: English, built in")
    elseif rows then
        print(("[gg_lib] language: %s, %d strings translated -- the rest fall back to English"):format(code, count(rows)))
    else
        print(("^3[gg_lib] language: %s is set but has no readable file -- everything is English^0"):format(code))
    end

    local names = {}

    for _, option in ipairs(LocaleNames.options()) do names[#names + 1] = option.value end

    print(("[gg_lib] available: %s"):format(table.concat(names, ", ")))
end, true)

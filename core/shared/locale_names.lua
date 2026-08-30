
LocaleNames = LocaleNames or {}

local NAMES = {
    { code = "en",    label = "English" },
    { code = "de",    label = "Deutsch" },
    { code = "es",    label = "Espanol" },
    { code = "fr",    label = "Francais" },
    { code = "nl",    label = "Nederlands" },
    { code = "pt-br", label = "Portugues (Brasil)" },

    { code = "ja",    label = "Japanese" },
    { code = "zh-cn", label = "Chinese (Simplified)" },
}

function LocaleNames.label(code)
    for _, row in ipairs(NAMES) do
        if row.code == code then return row.label end
    end

    return code
end

-- A file copied from English has every key and none of the work, so a language
-- is only offered once a quarter of its strings actually differ.
local MIN_TRANSLATED = 0.25

local function load(code)
    local body = LoadResourceFile(GetCurrentResourceName(), ("locales/%s.json"):format(code))

    if type(body) ~= "string" or body == "" then return nil end

    local ok, value = pcall(json.decode, body)

    return ok and type(value) == "table" and value or nil
end

local ready = {}

function LocaleNames.present(code)
    if code == "en" then return true end
    if ready[code] ~= nil then return ready[code] end

    local rows = load(code)
    local english = load("en")

    if not rows or not english then
        ready[code] = false

        return false
    end

    local total, done = 0, 0

    for key, value in pairs(english) do
        total = total + 1

        if type(rows[key]) == "string" and rows[key] ~= "" and rows[key] ~= value then done = done + 1 end
    end

    ready[code] = total > 0 and (done / total) >= MIN_TRANSLATED

    return ready[code]
end

function LocaleNames.forget()
    ready = {}
end

function LocaleNames.options()
    local out = {}

    for _, row in ipairs(NAMES) do
        if LocaleNames.present(row.code) then
            out[#out + 1] = { value = row.code, label = row.label }
        end
    end

    return out
end

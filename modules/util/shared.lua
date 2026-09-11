gg.util = gg.util or {}

local SEPARATORS = {
    ["1,234.56"] = { group = ",", decimal = "." },
    ["1.234,56"] = { group = ".", decimal = "," },
    ["1 234,56"] = { group = " ", decimal = "," },
    ["1234.56"]  = { group = "",  decimal = "." },
}

local SYMBOLS = {
    USD = "$", CAD = "CA$", AUD = "A$", NZD = "NZ$", SGD = "S$", HKD = "HK$",
    TWD = "NT$", BRL = "R$", MXN = "MX$", ARS = "AR$", CLP = "CLP$", COP = "COL$",
    UYU = "$U", BSD = "$", BBD = "$", BMD = "$", BZD = "$", BND = "$", FJD = "$",
    GYD = "$", JMD = "$", KYD = "$", LRD = "$", NAD = "$", SBD = "$", SRD = "$",
    TTD = "$", XCD = "$", ZWL = "$",

    EUR = "€", GBP = "£", JPY = "¥", CNY = "¥", INR = "₹", KRW = "₩",
    KPW = "₩", RUB = "₽", UAH = "₴", TRY = "₺", ILS = "₪", VND = "₫",
    THB = "฿", PHP = "₱", NGN = "₦", GHS = "₵", CRC = "₡", PYG = "₲",
    LAK = "₭", MNT = "₮", KZT = "₸", AZN = "₼", GEL = "₾", BDT = "৳",
    KHR = "៛", PLN = "zł", CZK = "Kč", HUF = "Ft", ISK = "kr", NOK = "kr",
    SEK = "kr", DKK = "kr", CHF = "CHF", ZAR = "R", EGP = "E£", LBP = "L£",
    SYP = "S£", SDG = "SDG", SHP = "£", FKP = "£", GIP = "£", JEP = "£",

    PKR = "₨", LKR = "₨", NPR = "₨", MUR = "₨", SCR = "₨", IDR = "Rp",
    MYR = "RM", VES = "Bs.", BOB = "Bs.", PEN = "S/", GTQ = "Q", HNL = "L",
    NIO = "C$", DOP = "RD$", CUP = "₱", SVC = "₡", PAB = "B/.",
}

local SUFFIXED = { PLN = true, CZK = true, HUF = true, SEK = true, NOK = true, DKK = true, ISK = true }

local DEFAULT_SEPARATORS = SEPARATORS["1,234.56"]

local function genericGeneral()
    return cfg and cfg.generic and cfg.generic.general or nil
end

local function groupDigits(digits, separator)
    if separator == "" then return digits end

    local marked = digits:reverse():gsub("(%d%d%d)", "%1\1"):reverse()

    if marked:sub(1, 1) == "\1" then marked = marked:sub(2) end

    return (marked:gsub("\1", separator))
end

function gg.util.formatNumber(number, decimals)
    local general    = genericGeneral()
    local separators = SEPARATORS[general and general.number_format] or DEFAULT_SEPARATORS

    number   = tonumber(number) or 0
    decimals = tonumber(decimals) or 0

    local text = ("%%.%df"):format(decimals):format(math.abs(number))
    local digits, fraction = text:match("^(%d+)%.?(%d*)$")

    if not digits then return text end

    local formatted = groupDigits(digits, separators.group)

    if fraction ~= "" then
        formatted = formatted .. separators.decimal .. fraction
    end

    return (number < 0 and "-" or "") .. formatted
end

function gg.util.formatMoney(amount, decimals)
    local general  = genericGeneral()
    local currency = general and general.currency_type or "USD"
    local formatted = gg.util.formatNumber(amount, decimals)

    local symbol = SYMBOLS[currency]

    if not symbol then
        return ("%s %s"):format(currency, formatted)
    end

    if SUFFIXED[currency] then
        return ("%s %s"):format(formatted, symbol)
    end

    return symbol .. formatted
end

local UNITS = {
    metric = {
        short  = { per_metre = 1.0,         unit = "m",  decimals = 0 },
        long   = { per_metre = 0.001,       unit = "km", decimals = 1 },
        switch = 1000.0,
        speed  = { per_mps = 3.6,           unit = "km/h", decimals = 0 },
    },
    imperial = {
        short  = { per_metre = 1.09361,     unit = "yd", decimals = 0 },
        long   = { per_metre = 0.000621371, unit = "mi", decimals = 1 },
        switch = 548.64,
        speed  = { per_mps = 2.23694,       unit = "mph", decimals = 0 },
    },
}

local DEFAULT_UNITS = "metric"

function gg.util.units()
    local general = genericGeneral()
    local chosen  = general and general.unit_system

    return UNITS[chosen] and chosen or DEFAULT_UNITS
end

local function round(value, decimals)
    if not decimals or decimals <= 0 then
        return math.floor(value + 0.5)
    end

    local factor = 10 ^ decimals

    return math.floor(value * factor + 0.5) / factor
end

function gg.util.distance(metres, longFrom)
    local system = UNITS[gg.util.units()]

    metres = math.max(0, tonumber(metres) or 0)

    local scale = metres >= (tonumber(longFrom) or system.switch) and system.long or system.short

    return round(metres * scale.per_metre, scale.decimals), scale.unit, scale.decimals
end

function gg.util.formatDistance(metres, longFrom)
    local value, unit, decimals = gg.util.distance(metres, longFrom)

    return ("%s %s"):format(gg.util.formatNumber(value, decimals), unit)
end

function gg.util.speed(mps)
    local scale = UNITS[gg.util.units()].speed

    return round(math.max(0, tonumber(mps) or 0) * scale.per_mps, scale.decimals), scale.unit, scale.decimals
end

function gg.util.formatSpeed(mps)
    local value, unit, decimals = gg.util.speed(mps)

    return ("%s %s"):format(gg.util.formatNumber(value, decimals), unit)
end

--- Splits a stored color into the four channels every native asks for.
--- Accepts #rrggbbaa, #rrggbb and #rgb, so a default written by hand works
--- without anybody having to remember the opacity.
function gg.util.rgba(value, fallback)
    local hex = string.match(tostring(value or ""), "^#?(%x+)$")

    if not (hex and (#hex == 3 or #hex == 6 or #hex == 8)) then
        hex = string.match(tostring(fallback or ""), "^#?(%x+)$")
    end

    if not (hex and (#hex == 3 or #hex == 6 or #hex == 8)) then return 255, 255, 255, 255 end

    if #hex == 3 then hex = (hex:gsub("(%x)", "%1%1")) end

    return tonumber(hex:sub(1, 2), 16) or 255,
           tonumber(hex:sub(3, 4), 16) or 255,
           tonumber(hex:sub(5, 6), 16) or 255,
           #hex == 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
end

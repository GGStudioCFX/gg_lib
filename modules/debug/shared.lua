gg.debug = gg.debug or {}

local RESOURCE = GetCurrentResourceName()
local SERVER   = IsDuplicityVersion()

local OWN_PATH     = "settings.debug"
local GENERIC_PATH = "debug.enabled"

local function enabled()
    if not settings then return false end

    if settings.read then
        local own = settings.read(OWN_PATH)

        if own ~= nil then return own == true end
    end

    if settings.generic and settings.generic.get then
        return settings.generic.get(GENERIC_PATH) == true
    end

    return false
end

gg.debug.on = enabled

local TINT, RESET = SERVER and "\27[35m" or "^5", SERVER and "\27[0m" or "^7"

local function where(level)
    local info = debug.getinfo(level, "Sl")

    if not info then return "?" end

    return ("%s:%s"):format(info.short_src or "?", info.currentline or "?")
end

local function emit(prefix, at, parts)
    local out = { ("%s[DEBUG]%s"):format(TINT, RESET), prefix }

    for index = 1, parts.n do out[#out + 1] = tostring(parts[index]) end

    out[#out + 1] = ("[%s]"):format(at)

    print(table.concat(out, "  "))
end

local MAX_DEPTH = 4
local MAX_KEYS  = 40

local function render(value, depth, seen, out)
    if type(value) ~= "table" then
        out[#out + 1] = type(value) == "string" and ("%q"):format(value) or tostring(value)
        return
    end

    if seen[value] then
        out[#out + 1] = "<cycle>"
        return
    end

    if depth > MAX_DEPTH then
        out[#out + 1] = "{...}"
        return
    end

    seen[value] = true

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end

    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)

    local pad, inner = ("  "):rep(depth), ("  "):rep(depth + 1)

    if #keys == 0 then
        out[#out + 1] = "{}"
        seen[value] = nil

        return
    end

    out[#out + 1] = "{\n"

    for index = 1, math.min(#keys, MAX_KEYS) do
        local key = keys[index]

        out[#out + 1] = ("%s%s = "):format(inner, tostring(key))
        render(value[key], depth + 1, seen, out)
        out[#out + 1] = ",\n"
    end

    if #keys > MAX_KEYS then
        out[#out + 1] = ("%s... %d more\n"):format(inner, #keys - MAX_KEYS)
    end

    out[#out + 1] = pad .. "}"

    seen[value] = nil
end

local function pretty(value)
    local out = {}

    render(value, 0, {}, out)

    return table.concat(out)
end

local function elapsed()
    if GetGameTimer then return GetGameTimer() end

    return os.clock() * 1000
end

local function channel(tag)
    tag = type(tag) == "string" and tag ~= "" and tag or nil

    local prefix = tag and ("%s:%s"):format(RESOURCE, tag) or RESOURCE

    local self = {}

    self.on = enabled

    function self.dump(label, value)
        if not enabled() then return end

        emit(prefix, where(3), table.pack(("%s = %s"):format(tostring(label), pretty(value))))
    end

    function self.timer(label)
        if not enabled() then return function() end end

        local started = elapsed()

        return function()
            if not enabled() then return end

            emit(prefix, where(3), table.pack(tostring(label), ("%.1fms"):format(elapsed() - started)))
        end
    end

    function self.when(fn)
        if not enabled() or type(fn) ~= "function" then return end

        local ok, err = pcall(fn)

        if not ok then
            emit(prefix, where(3), table.pack("debug block failed:", tostring(err)))
        end
    end

    return setmetatable(self, {
        __call = function(_, ...)
            if not enabled() then return end

            emit(prefix, where(3), table.pack(...))
        end,
    })
end

setmetatable(gg.debug, {
    __call = function(_, tag) return channel(tag) end,
})

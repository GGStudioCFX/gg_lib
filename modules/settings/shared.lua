
settings = settings or {}
cfg = cfg or {}

settings.schema      = {}  -- path -> definition
settings.editors     = {}
settings.order       = {}  -- declaration order, so the editor reads top to bottom
settings.groups      = {}  -- group id -> meta
settings.group_order = {}

settings.info = {
    id    = GetCurrentResourceName(),
    label = GetCurrentResourceName(),
    icon  = "fa-gear",
    order = 100,
}

local derives  = {}
local listeners = {}
local resolved = false

local function logError(message)
    if gg and gg.print and gg.print.error then
        gg.print.error(message)
        return
    end

    print(("[ERROR] [settings] %s"):format(message))
end

local function logInfo(message)
    if gg and gg.print and gg.print.log then
        gg.print.log(message)
        return
    end

    print(("[settings] %s"):format(message))
end

local function logDebug(message)
    if gg and gg.print and gg.print.debug then
        gg.print.debug(message)
    end
end

local function splitPath(path)
    local parts = {}

    for part in string.gmatch(path, "[^%.%[%]]+") do
        parts[#parts + 1] = tonumber(part) or part
    end

    return parts
end

settings.splitPath = splitPath

local function deepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = deepCopy(entry)
    end

    return copy
end

settings.deepCopy = deepCopy

function settings.read(path, root)
    local node = root or cfg
    local parts = splitPath(path)

    for index = 1, #parts do
        if type(node) ~= "table" then return nil end
        node = node[parts[index]]
    end

    return node
end

function settings.write(path, value, root)
    local node = root or cfg
    local parts = splitPath(path)

    for index = 1, #parts - 1 do
        local key = parts[index]

        if type(node[key]) ~= "table" then
            node[key] = {}
        end

        node = node[key]
    end

    node[parts[#parts]] = value

    return value
end

settings.rowActions = settings.rowActions or {}

settings.actions = settings.actions or {}

local validators = {}

validators.action = function()
    return false, "an action holds no value"
end

validators.boolean = function(_, value)
    if type(value) == "boolean" then return true, value end
    if value == "true"  then return true, true  end
    if value == "false" then return true, false end

    return false, "expected a true/false value"
end

local function finite(value)
    local number = tonumber(value)

    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end

    return number
end

validators.number = function(def, value)
    local number = finite(value)
    if not number then return false, "expected a number" end

    if def.min and number < def.min then
        return false, ("must be at least %s"):format(def.min)
    end

    if def.max and number > def.max then
        return false, ("must be at most %s"):format(def.max)
    end

    return true, number
end

validators.integer = function(def, value)
    local ok, number = validators.number(def, value)
    if not ok then return false, number end

    return true, math.floor(number + 0.5)
end

validators.percent = validators.number
validators.currency = validators.integer
validators.duration = validators.integer

validators.blipcolor = function(_, value)
    local number = tonumber(value)
    if not number then return false, "expected a blip color" end

    number = math.floor(number)
    if number < 0 or number > 85 then return false, "is not a blip color (0-85)" end

    return true, number
end

validators.vehiclecolor = function(_, value)
    if type(value) == "table" then
        local r, g, b = tonumber(value.r), tonumber(value.g), tonumber(value.b)

        if not r or not g or not b then return false, "expected r, g and b" end

        local function channel(n)
            return math.max(0, math.min(255, math.floor(n + 0.5)))
        end

        return true, { r = channel(r), g = channel(g), b = channel(b) }
    end

    local number = tonumber(value)
    if not number then return false, "expected a paint index or an r/g/b colour" end

    number = math.floor(number)
    if number < 0 or number > 255 then return false, "is not a paint index (0-255)" end

    return true, number
end

validators.ped = function(_, value)
    if type(value) ~= "string" then return false, "expected a ped model name" end

    local model = value:gsub("%s", "")
    if model == "" then return false, "cannot be empty" end

    if not model:match("^[%w_]+$") then
        return false, "is not a model name (letters, numbers and underscores only)"
    end

    return true, model:lower()
end

validators.vehicle = validators.ped

local function outfitSlots(value)
    if type(value) ~= "table" then return {} end

    local out = {}

    for name, slot in pairs(value) do
        if type(name) == "string" and type(slot) == "table" then
            local drawable = tonumber(slot.drawable)

            if drawable then
                out[name] = {
                    drawable = math.floor(drawable),
                    texture  = math.max(0, math.floor(tonumber(slot.texture) or 0)),
                }
            end
        end
    end

    return out
end

validators.outfit = function(_, value)
    if type(value) ~= "table" then return false, "expected an outfit" end

    local out = {}

    for _, gender in ipairs({ "male", "female" }) do
        local body = value[gender]

        out[gender] = {
            components = outfitSlots(type(body) == "table" and body.components or nil),
            props      = outfitSlots(type(body) == "table" and body.props or nil),
        }
    end

    return true, out
end

validators.item = function(_, value)
    if type(value) ~= "string" then return false, "expected an item name" end

    local name = value:gsub("%s", "")
    if name == "" then return false, "cannot be empty" end

    if not name:match("^[%w_%-]+$") then
        return false, "is not an item name (letters, numbers, underscores and hyphens only)"
    end

    return true, name:lower()
end

validators.coords = function(_, value)
    local kind = type(value)

    if kind ~= "table" and kind ~= "userdata" and kind ~= "vector3" and kind ~= "vector4" then
        return false, "expected a position"
    end

    local out = {}

    for _, key in ipairs({ "x", "y", "z" }) do
        local number = finite(value[key])
        if not number then return false, ("is missing its %s"):format(key) end

        out[key] = number
    end

    local heading = finite(value.heading) or finite(value.w) or 0
    out.heading = heading % 360

    return true, out
end

validators.blipsprite = function(_, value)
    local number = finite(value)
    if not number then return false, "expected a blip sprite" end

    number = math.floor(number)
    if number < 0 then return false, "is not a blip sprite" end

    return true, number
end

validators.string = function(def, value)
    if type(value) ~= "string" then return false, "expected text" end

    if def.max_length and #value > def.max_length then
        return false, ("must be %s characters or fewer"):format(def.max_length)
    end

    if def.pattern and not string.match(value, def.pattern) then
        return false, def.pattern_help or "does not match the required format"
    end

    return true, value
end

validators.image = function(_, value)
    if value == nil then return true, "" end
    if type(value) ~= "string" then return false, "expected a file name" end

    local name = value:gsub("%s", "")

    if name == "" then return true, "" end

    if name:find("/", 1, true) or name:find("\\", 1, true) then
        return false, "is a file name, not a path"
    end

    return true, name
end

validators.enum = function(def, value)
    local choices = def.options
    if type(choices) == "function" then
        local ok, result = pcall(choices)
        choices = ok and result or nil
    end
    if type(choices) ~= "table" then return false, "options are unavailable" end

    for _, option in ipairs(choices) do
        local candidate = type(option) == "table" and option.value or option
        if candidate == value then return true, value end
    end

    -- Older pickers saved numeric options as text. Restore the declared type.
    if type(value) == "string" then
        for _, option in ipairs(choices) do
            local candidate = type(option) == "table" and option.value or option
            if type(candidate) == "number" and tostring(candidate) == value then return true, candidate end
        end
    elseif type(value) == "number" then
        for _, option in ipairs(choices) do
            local candidate = type(option) == "table" and option.value or option
            if type(candidate) == "string" and (candidate == tostring(value) or tonumber(candidate) == value) then return true, candidate end
        end
    end

    local shown = {}
    for index, option in ipairs(choices) do
        if index > 20 then shown[#shown + 1] = "…" break end
        local candidate = type(option) == "table" and option.value or option
        shown[#shown + 1] = type(candidate) == "string" and ('"%s"'):format(candidate) or tostring(candidate)
    end

    return false, ("is not one of the allowed options: %s"):format(table.concat(shown, ", "))
end

validators.color = function(_, value)
    if type(value) ~= "string" then return false, "expected a color string" end

    if string.match(value, "^#%x%x%x%x%x%x$")
        or string.match(value, "^#%x%x%x$")
        or string.match(value, "^rgba?%(%s*%d+%s*,%s*%d+%s*,%s*%d+%s*[,%)]")
    then
        return true, value
    end

    return false, "expected a hex or rgb() color"
end

local function hexByte(value)
    local number = math.floor(tonumber(value) or 0)

    if number < 0 then number = 0 elseif number > 255 then number = 255 end

    return string.format("%02x", number)
end

local function toHex8(value)
    -- Two fields left over from when a color and its opacity were separate
    -- settings. One value now, so the pair is folded into it on the way in.
    if type(value) == "table" then
        local base = toHex8(value.color)

        if not base then return nil end

        return base:sub(1, 7) .. hexByte(value.alpha == nil and 255 or value.alpha)
    end

    if type(value) ~= "string" then return nil end

    local body = string.match(value, "^#(%x+)$")

    if body and #body == 3 then body = (body:gsub("(%x)", "%1%1")) end
    if body and #body == 6 then return ("#%sff"):format(body):lower() end
    if body and #body == 8 then return ("#%s"):format(body):lower() end

    local red, green, blue, alpha = string.match(value, "^rgba?%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*([%d%.]*)%s*%)$")

    if not red then return nil end

    local opacity = 255

    if alpha and alpha ~= "" then
        local number = tonumber(alpha) or 1

        -- Written this way the last channel runs 0 to 1, but every native that
        -- takes one counts it to 255.
        opacity = number <= 1 and number * 255 or number
    end

    return ("#%s%s%s%s"):format(hexByte(red), hexByte(green), hexByte(blue), hexByte(opacity))
end

validators.rgba = function(_, value)
    local hex = toHex8(value)

    if hex then return true, hex end

    return false, "expected a color with an opacity, like #rrggbbaa"
end

validators.time = function(_, value)
    if type(value) ~= "string" then return false, "expected a HH:MM time" end

    local hour, minute = string.match(value, "^(%d%d?):(%d%d)$")
    if not hour then return false, "expected a HH:MM time" end

    hour, minute = tonumber(hour), tonumber(minute)
    if hour > 23 or minute > 59 then return false, "is not a valid time of day" end

    return true, ("%02d:%02d"):format(hour, minute)
end

validators.keybind = function(_, value)
    if type(value) ~= "string" or #value == 0 then return false, "expected a key" end

    return true, string.upper(value)
end

validators.object = function(def, value)
    if type(value) ~= "table" then return false, "expected a group of values" end

    local out = {}

    for _, field in ipairs(def.fields or {}) do
        local raw = settings.read(field.key, value)

        if field.nullable then
            if raw ~= nil and raw ~= false then
                local ok, result = settings.validate(field, raw)
                if not ok then
                    return false, ("%s %s"):format(field.label or field.key, result)
                end

                settings.write(field.key, result, out)
            end

            goto continue
        end

        if raw == nil then
            raw = settings.read(field.key, def.default or {})
        end

        if raw ~= nil then
            local ok, result = settings.validate(field, raw)
            if not ok then
                return false, ("%s %s"):format(field.label or field.key, result)
            end

            settings.write(field.key, result, out)
        end

        ::continue::
    end

    -- A pair of bounds that crossed passes each field on its own and then
    -- empties every random range drawn from it.
    for _, field in ipairs(def.fields or {}) do
        local stem = field.key:match("^(.*)min$")

        if stem and (stem == "" or stem:sub(-1) == ".") then
            local partner = nil
            for _, other in ipairs(def.fields) do
                if other.key == stem .. "max" then partner = other end
            end

            local low, high = settings.read(field.key, out), partner and settings.read(partner.key, out)

            if type(low) == "number" and type(high) == "number" and low > high then
                return false, ("%s is above %s"):format(field.label or field.key, partner.label or partner.key)
            end
        end
    end

    return true, out
end

validators.list = function(def, value)
    if type(value) ~= "table" then return false, "expected a list" end

    -- Rows keyed by anything but 1..n are not a list, and a hole in the
    -- middle makes its length a guess.
    local seen = 0
    for _ in pairs(value) do seen = seen + 1 end
    if seen ~= #value then return false, "expected a list" end

    if def.min_items and #value < def.min_items then
        return false, ("needs at least %s entries"):format(def.min_items)
    end

    if def.max_items and #value > def.max_items then
        return false, ("allows at most %s entries"):format(def.max_items)
    end

    -- The column a row is filed under is the one thing a default cannot
    -- stand in for: a row without it is some other row, and two rows with
    -- the same one are one row.
    local identity = def.merge_key or def.auto_key

    if identity and def.item then
        local column = nil
        for _, field in ipairs(def.item) do
            if field.key == identity then column = field end
        end

        local named = column and column.label or identity
        local seen  = {}

        for index = 1, #value do
            local held = type(value[index]) == "table" and settings.read(identity, value[index]) or nil

            if held == nil or held == "" then
                return false, ("entry %d is missing its %s"):format(index, named)
            end

            local first = seen[tostring(held)]
            if first then
                return false, ("entry %d has the same %s as entry %d"):format(index, named, first)
            end

            seen[tostring(held)] = index
        end
    end

    local out = {}

    for index = 1, #value do
        local row = value[index]

        if not def.item then
            local ok, result = settings.validate({ type = def.item_type or "string" }, row)
            if not ok then
                return false, ("entry %d %s"):format(index, result)
            end

            out[index] = result
        else
            local ok, result = validators.object({ fields = def.item, default = def.item_default }, row)
            if not ok then
                return false, ("entry %d: %s"):format(index, result)
            end

            out[index] = result
        end
    end

    return true, out
end

local vehicle_numbers = {
        "plateIndex", "paintType1", "paintType2", "pearlescentColor",
        "interiorColor", "dashboardColor", "wheelColor", "wheelWidth",
        "wheelSize", "wheels", "windowTint", "xenonColor", "modSpoilers",
        "modFrontBumper", "modRearBumper", "modSideSkirt", "modExhaust",
        "modFrame", "modGrille", "modHood", "modFender", "modRightFender",
        "modRoof", "modEngine", "modBrakes", "modTransmission", "modHorns",
        "modSuspension", "modArmor", "modNitrous", "modFrontWheels",
        "modBackWheels", "modPlateHolder", "modVanityPlate", "modTrimA",
        "modOrnaments", "modDashboard", "modDial", "modDoorSpeaker",
        "modSeats", "modSteeringWheel", "modShifterLeavers", "modAPlate",
        "modSpeakers", "modTrunk", "modHydrolic", "modEngineBlock",
        "modAirFilter", "modStruts", "modArchCover", "modAerials",
        "modTrimB", "modTank", "modWindows", "modDoorR", "modLivery",
        "modRoofLivery", "modLightbar", "livery",
}

local vehicle_booleans = {
        "modTurbo", "modSubwoofer", "modSmokeEnabled", "modHydraulics",
        "modXenon", "modCustomTiresF", "modCustomTiresR", "driftTyres",
}

local vehicle_fractional = { wheelWidth = true, wheelSize = true }

local function channels(value)
    if type(value) ~= "table" then return nil end

    local r = tonumber(value[1] or value.r)
    local g = tonumber(value[2] or value.g)
    local b = tonumber(value[3] or value.b)

    if not r or not g or not b then return nil end

    local function clamp(n) return math.max(0, math.min(255, math.floor(n))) end

    return { clamp(r), clamp(g), clamp(b) }
end

validators.vehicleprops = function(_, value)
    if type(value) ~= "table" then return false, "expected a set of vehicle properties" end

    local out = {}

    for _, key in ipairs(vehicle_numbers) do
        local number = tonumber(value[key])

        if number then
            out[key] = vehicle_fractional[key] and number + 0.0 or math.floor(number)
        end
    end

    for _, key in ipairs(vehicle_booleans) do
        if type(value[key]) == "boolean" then out[key] = value[key] end
    end

    for _, key in ipairs({ "color1", "color2" }) do
        local paint = value[key]

        if type(paint) == "number" then
            out[key] = math.floor(paint)
        else
            out[key] = channels(paint)
        end
    end

    out.neonColor = channels(value.neonColor)
    out.tyreSmokeColor = channels(value.tyreSmokeColor)

    if type(value.neonEnabled) == "table" then
        local sides = {}

        for side = 1, 4 do sides[side] = value.neonEnabled[side] == true end

        out.neonEnabled = sides
    end

    if type(value.extras) == "table" then
        local extras = {}

        for id, disabled in pairs(value.extras) do
            local slot = tonumber(id)

            if slot and slot >= 0 and slot <= 20 then
                extras[slot] = (disabled == 1 or disabled == true) and 1 or 0
            end
        end

        out.extras = extras
    end

    return true, out
end

settings.validators = validators

function settings.validate(def, value)
    local validator = validators[def.type or "string"]
    local ok, result = true, value

    if validator then ok, result = validator(def, value) end
    if not ok then return false, result end

    if type(def.validate) == "function" then
        local ran, valid, reason = pcall(def.validate, result)

        if not ran then
            logError(("Setting '%s' validation failed: %s"):format(tostring(def.path or def.key), valid))
            return false, "could not validate this setting"
        end

        if valid ~= true then return false, reason or "is not valid" end
    end

    return true, result
end

local function normalizeNeeds(list)
    if type(list) ~= "table" then return {} end

    local out = {}

    for index = 1, #list do
        local need = list[index]

        if type(need) == "string" and need ~= "" then
            out[#out + 1] = { name = need }
        elseif type(need) == "table" and type(need.name) == "string" and need.name ~= "" then
            out[#out + 1] = {
                name     = need.name,
                why      = type(need.why) == "string" and need.why or nil,
                optional = need.optional == true or nil,
            }
        end
    end

    return out
end

function settings.requires(spec)
    settings.info.requires = {
        items     = normalizeNeeds(spec and spec.items),
        resources = normalizeNeeds(spec and spec.resources),
    }

    return settings.info.requires
end

local DEBUG_PATH  = "settings.debug"
local DEBUG_GROUP = "developer"

local UPDATES_GROUP = "__updates__"

local function versionParts(value)
    local parts = {}

    for part in (tostring(value):gsub("^[vV]", "")):gmatch("%d+") do
        parts[#parts + 1] = tonumber(part)
    end

    return parts
end

local function compareVersions(left, right)
    local a, b = versionParts(left), versionParts(right)

    for index = 1, math.max(#a, #b) do
        local diff = (a[index] or 0) - (b[index] or 0)

        if diff ~= 0 then return diff end
    end

    return 0
end

function settings.updates(list)
    if type(list) ~= "table" then return nil end

    local out, seen = {}, {}

    for _, row in ipairs(list) do
        if type(row) == "table" then
            local version = type(row.version) == "string" and (row.version:gsub("^[vV]", ""))
                or (type(row.version) == "number" and tostring(row.version))
                or nil

            if version and version ~= "" and not seen[version] then
                seen[version] = true

                local changes = {}

                for _, change in ipairs(type(row.changes) == "table" and row.changes or {}) do
                    if type(change) == "string" and change ~= "" then changes[#changes + 1] = change end
                end

                local kind = type(row.kind) == "string" and row.kind:lower() or nil

                out[#out + 1] = {
                    version   = version,
                    at        = (type(row.at) == "string" or type(row.at) == "number") and row.at or nil,
                    title     = type(row.title) == "string" and row.title or nil,
                    changes   = changes,
                    kind      = (kind == "major" or kind == "feature" or kind == "fix") and kind or "feature",
                    important = row.important == true,
                }
            end
        end
    end

    if #out == 0 then return nil end

    table.sort(out, function(left, right) return compareVersions(left.version, right.version) > 0 end)

    return out
end

local function defineDebug()
    if settings.schema[DEBUG_PATH] then return end

    settings.group(DEBUG_GROUP, {
        label = "Developer",
        icon  = "fa-bug",
        help  = "Console output for working out what this script is doing. Off on a live server.",
    })

    settings.define(DEBUG_PATH, {
        group = DEBUG_GROUP,
        label = "Debug Mode",
        help  = "Print what this script is doing to the server console, and to F8 on the client. Takes effect immediately -- no restart, and no file to edit.",
        type  = "boolean",
        default = false,
    })
end

function settings.script(info)
    for key, value in pairs(info or {}) do
        if key == "requires" then
            settings.requires(value)
        else
            settings.info[key] = value
        end
    end

    defineDebug()

    return settings.info
end

function settings.group(id, meta)
    if settings.groups[id] then
        for key, value in pairs(meta or {}) do
            settings.groups[id][key] = value
        end

        return settings.groups[id]
    end

    settings.groups[id] = {
        id    = id,
        label = (meta and meta.label) or id,
        icon  = meta and meta.icon,
        help  = meta and meta.help,
    }

    settings.group_order[#settings.group_order + 1] = id

    return settings.groups[id]
end

function settings.isSecret(path)
    local def = settings.schema[path]

    return def ~= nil and def.server_only == true
end

function settings.editor(id, definition)
    if type(id) ~= "string" or not id:match("^[%w_%-]+$") or type(definition) ~= "table" then return false end
    local preview = definition.preview
    if type(preview) ~= "string" or not preview:match("^[%w_/%-%.]+%.html$") or preview:find("..", 1, true) or preview:sub(1, 1) == "/" then return false end
    if type(definition.sections) ~= "table" then return false end

    local editor = settings.deepCopy(definition)
    editor.id = id
    settings.editors[id] = editor
    settings.group(id, { label = editor.label or id, icon = editor.icon or "fa-palette", help = editor.help })
    settings.groups[id].editor = true
    return true
end

function settings.action(path, def)
    def = def or {}
    def.type = "action"

    local handler = def.run
    def.run = nil

    settings.define(path, def)

    if handler then settings.actions[path] = handler end
end

function settings.rowAction(id, handler)
    if type(id) ~= "string" or type(handler) ~= "function" then return end

    settings.rowActions[id] = handler
end

function settings.define(path, def)
    if settings.schema[path] then
        logError(("Setting '%s' declared twice"):format(path))
        return
    end

    def.path  = path
    def.type  = def.type or "string"
    def.group = def.group or "general"
    def.label = def.label or path

    if def.live == nil then def.live = true end

    if def.server_only and def.default ~= nil and def.default ~= "" then
        logError(("Setting '%s' is server only but ships a default value; set it on the settings page instead"):format(path))
    end

    if not settings.groups[def.group] then
        settings.group(def.group, { label = def.group })
    end

    settings.schema[path] = def
    settings.order[#settings.order + 1] = path

    if def.server_only and not IsDuplicityVersion() then
        return def
    end

    settings.write(path, deepCopy(def.default))

    return def
end

settings.accounts = {
    { value = "cash",  label = "Cash" },
    { value = "bank",  label = "Bank" },
    { value = "black", label = "Black Money" },
}

settings.speechLines = {
    { value = "GENERIC_HI",              label = "Greeting · Hello" },
    { value = "GENERIC_HOWS_IT_GOING",   label = "Greeting · How's it going" },
    { value = "GENERIC_WHATEVER",        label = "Greeting · Whatever" },
    { value = "GENERIC_HOWDY",           label = "Greeting · Howdy" },
    { value = "CHAT_STATE",              label = "Greeting · Small talk" },
    { value = "CHAT_RESP",               label = "Greeting · Small talk reply" },

    { value = "GENERIC_BYE",             label = "Farewell · Goodbye" },
    { value = "GENERIC_THANKS",          label = "Farewell · Thanks" },
    { value = "GENERIC_INSULT_MED",      label = "Farewell · Mild insult" },
    { value = "GENERIC_INSULT_HIGH",     label = "Farewell · Strong insult" },

    { value = "GENERIC_CURSE_MED",       label = "Annoyed · Mild curse" },
    { value = "GENERIC_CURSE_HIGH",      label = "Annoyed · Strong curse" },
    { value = "BLOCKED_GENERIC",         label = "Annoyed · You're in the way" },
    { value = "PROVOKE_GENERIC",         label = "Annoyed · Provoked" },
    { value = "PROVOKE_TRESPASS",        label = "Annoyed · Get out of here" },
    { value = "SHOUT_THREATEN_PED",      label = "Annoyed · Threaten" },

    { value = "GENERIC_SHOCKED_MED",     label = "Reaction · Surprised" },
    { value = "GENERIC_SHOCKED_HIGH",    label = "Reaction · Very surprised" },
    { value = "GENERIC_FRIGHTENED_MED",  label = "Reaction · Nervous" },
    { value = "GENERIC_FRIGHTENED_HIGH", label = "Reaction · Scared" },
    { value = "GENERIC_FUCK_YOU",        label = "Reaction · Told off" },
    { value = "GENERIC_WAR_CRY",         label = "Reaction · War cry" },

    { value = "APPLAUD",                 label = "Approval · Applaud" },
    { value = "CHEER",                   label = "Approval · Cheer" },
    { value = "GENERIC_YES",             label = "Approval · Yes" },
    { value = "GENERIC_NO",              label = "Approval · No" },

    { value = "COUGH",                   label = "Idle · Cough" },
    { value = "WHISTLE",                 label = "Idle · Whistle" },
    { value = "GENERIC_FRUSTRATED_HIGH", label = "Idle · Frustrated" },
}

settings.speechParams = {
    { value = "SPEECH_PARAMS_STANDARD",                     label = "Standard" },
    { value = "SPEECH_PARAMS_ALLOW_REPEAT",                 label = "Allow repeat" },
    { value = "SPEECH_PARAMS_BEAT",                         label = "Beat" },

    { value = "SPEECH_PARAMS_FORCE",                        label = "Force" },
    { value = "SPEECH_PARAMS_FORCE_FRONTEND",               label = "Force, frontend" },
    { value = "SPEECH_PARAMS_FORCE_NO_REPEAT_FRONTEND",     label = "Force, frontend, no repeat" },

    { value = "SPEECH_PARAMS_FORCE_NORMAL",                 label = "Force, normal volume" },
    { value = "SPEECH_PARAMS_FORCE_NORMAL_CLEAR",           label = "Force, normal, clear" },
    { value = "SPEECH_PARAMS_FORCE_NORMAL_CRITICAL",        label = "Force, normal, critical" },

    { value = "SPEECH_PARAMS_FORCE_SHOUTED",                label = "Force, shouted" },
    { value = "SPEECH_PARAMS_FORCE_SHOUTED_CLEAR",          label = "Force, shouted, clear" },
    { value = "SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL",       label = "Force, shouted, critical" },

    { value = "SPEECH_PARAMS_FORCE_PRELOAD_ONLY",           label = "Preload only" },
    { value = "SPEECH_PARAMS_MEGAPHONE",                    label = "Megaphone" },
    { value = "SPEECH_PARAMS_HELI",                         label = "Helicopter" },
    { value = "SPEECH_PARAMS_INTERRUPT",                    label = "Interrupt" },
    { value = "SPEECH_PARAMS_INTERRUPT_SHOUTED",            label = "Interrupt, shouted" },
    { value = "SPEECH_PARAMS_INTERRUPT_SHOUTED_CLEAR",      label = "Interrupt, shouted, clear" },
    { value = "SPEECH_PARAMS_INTERRUPT_SHOUTED_CRITICAL",   label = "Interrupt, shouted, critical" },
    { value = "SPEECH_PARAMS_ADD_BLIP",                     label = "Add blip" },
}

settings.speechAnims = {
    { value = "",                                                    label = "None" },

    { value = "gestures@m@standing@casual|gesture_hello",             label = "Wave hello" },
    { value = "gestures@m@standing@casual|gesture_bye_soft",          label = "Wave goodbye" },
    { value = "gestures@m@standing@casual|gesture_bye_hard",          label = "Wave off" },
    { value = "gestures@m@standing@casual|gesture_come_here_soft",    label = "Come here" },
    { value = "gestures@m@standing@casual|gesture_come_here_hard",    label = "Get over here" },

    { value = "gestures@m@standing@casual|gesture_nod_yes_soft",      label = "Nod" },
    { value = "gestures@m@standing@casual|gesture_nod_yes_hard",      label = "Nod firmly" },
    { value = "gestures@m@standing@casual|gesture_nod_no_soft",       label = "Shake head" },
    { value = "gestures@m@standing@casual|gesture_nod_no_hard",       label = "Shake head firmly" },

    { value = "gestures@m@standing@casual|gesture_shrug_soft",        label = "Shrug" },
    { value = "gestures@m@standing@casual|gesture_shrug_hard",        label = "Shrug hard" },
    { value = "gestures@m@standing@casual|gesture_point",             label = "Point" },
    { value = "gestures@m@standing@casual|gesture_damn",              label = "Dismiss" },
    { value = "gestures@m@standing@casual|gesture_hand_up",           label = "Hand up" },
    { value = "gestures@m@standing@casual|gesture_easy_soft",         label = "Take it easy" },
    { value = "gestures@m@standing@casual|gesture_me_hard",           label = "Point at self" },
    { value = "gestures@m@standing@casual|gesture_you_hard",          label = "Point at you" },
    { value = "gestures@m@standing@casual|gesture_what_hard",         label = "What?" },
    { value = "gestures@m@standing@casual|gesture_why",               label = "Why?" },
    { value = "gestures@m@standing@casual|gesture_plead",             label = "Plead" },
}

settings.shape = {}
settings.column = {}
function settings.column.speech(prefix, label, help)
    return {
        { key = ("%s.name"):format(prefix),  label = ("%s Line"):format(label),     type = "enum", options = settings.speechLines,  help = help },
        { key = ("%s.param"):format(prefix), label = ("%s Delivery"):format(label), type = "enum", options = settings.speechParams },
        { key = ("%s.anim"):format(prefix),  label = ("%s Gesture"):format(label),  type = "enum", options = settings.speechAnims },
    }
end

function settings.column.account(key, label)
    return {
        key     = key or "account",
        label   = label or "Account",
        type    = "enum",
        options = settings.accounts,
    }
end

local function shaped(base, def)
    local out = {}

    for key, value in pairs(base) do out[key] = value end
    for key, value in pairs(def or {}) do out[key] = value end

    return out
end

function settings.shape.positions(def)
    return shaped({ type = "list", item_type = "coords" }, def)
end

function settings.shape.strings(def)
    return shaped({ type = "list", item_type = "string" }, def)
end

function settings.shape.rows(def)
    return shaped({ type = "list" }, def)
end

function settings.column.id(help)
    return { key = "id", label = "ID", type = "string", help = help }
end

function settings.column.label(label)
    return { key = "label", label = label or "Name", type = "string" }
end

function settings.column.level(label)
    return { key = "level", label = label or "Unlocks At Level", type = "integer", min = 1 }
end

function settings.column.zone(key, label)
    return {
        key = key,
        label = label,
        type = "list",
        item_type = "coords",
        nullable = true,
        edit_mode = "polygon",
    }
end

function settings.column.positions(key, label, options)
    options = options or {}

    return {
        key = key,
        label = label,
        type = "list",
        item_type = "coords",
        nullable = true,
        preview_model = options.model,
        min_gap = options.gap,
    }
end

function settings.derive(fn)
    derives[#derives + 1] = fn

    if resolved then
        local ok, err = pcall(fn)
        if not ok then
            logError(("Settings derive failed: %s"):format(err))
        end
    end
end

local function runDerives()
    for index = 1, #derives do
        local ok, err = pcall(derives[index])
        if not ok then
            logError(("Settings derive failed: %s"):format(err))
        end
    end
end

function settings.onChange(fn)
    listeners[#listeners + 1] = fn
end

function settings.isResolved()
    return resolved
end

local function mergeKeyedDefaults(def, value)
    if type(value) ~= "table" then return value end

    local present = {}

    for index = 1, #value do
        local row = value[index]

        if type(row) == "table" and row[def.merge_key] ~= nil then
            present[row[def.merge_key]] = true
        end
    end

    for _, row in ipairs(def.default or {}) do
        if type(row) == "table" and row[def.merge_key] ~= nil and not present[row[def.merge_key]] then
            value[#value + 1] = deepCopy(row)
        end
    end

    return value
end

settings.mergeKeyedDefaults = mergeKeyedDefaults

function settings.apply(overrides)
    local changed = {}

    for path, value in pairs(overrides or {}) do
        local def = settings.schema[path]

        if def then
            local migrated, migrationError = true, nil
            if type(def.migrate) == "function" then
                migrated, migrationError = pcall(def.migrate, deepCopy(value))
                if migrated then value = migrationError end
            end
            local ok, result = false, "could not migrate the stored value"
            if migrated then ok, result = settings.validate(def, value) end

            if ok then
                if def.merge_key then
                    result = mergeKeyedDefaults(def, result)
                end

                settings.write(path, result)
            else
                settings.write(path, deepCopy(def.default))
                logError(("Stored value for '%s' %s -- falling back to the default"):format(path, result))
            end

            changed[#changed + 1] = path
        end
    end

    return changed
end

function settings.resolve(overrides)
    local applied = settings.apply(overrides)

    if #applied > 0 then
        logDebug(("Settings: applied %d stored override(s)"):format(#applied))
    end

    runDerives()

    resolved = true

    if #applied > 0 then
        for index = 1, #listeners do
            local ok, err = pcall(listeners[index], applied)
            if not ok then
                logError(("Settings change handler failed on resolve: %s"):format(err))
            end
        end

        TriggerEvent("gg_settings:changed", applied)
    end

    TriggerEvent("gg_settings:resolved")
end

function settings.applyLive(overrides)
    local changed = settings.apply(overrides)
    if #changed == 0 then return changed end

    runDerives()

    for index = 1, #listeners do
        local ok, err = pcall(listeners[index], changed)
        if not ok then
            logError(("Settings change handler failed: %s"):format(err))
        end
    end

    TriggerEvent("gg_settings:changed", changed)

    return changed
end

local generic_listeners = {}
local generic_revision  = -1
local generic_resolved  = false

settings.generic = {}

settings.timezones = {
    UTC = 0, GMT = 0,
    EST = -5 * 3600, CST = -6 * 3600, MST = -7 * 3600, PST = -8 * 3600,
    AKST = -9 * 3600, HST = -10 * 3600,
    EDT = -4 * 3600, CDT = -5 * 3600, MDT = -6 * 3600, PDT = -7 * 3600,
    CET = 1 * 3600, EET = 2 * 3600, WET = 0,
    IST = 5.5 * 3600, CST_China = 8 * 3600, JST = 9 * 3600, KST = 9 * 3600,
    AEST = 10 * 3600, ACST = 9.5 * 3600, AWST = 8 * 3600,
}

function settings.generic.get(path)
    if not cfg.generic then return nil end

    return settings.read(path, cfg.generic)
end

function settings.generic.dailyReset()
    local clock = settings.generic.get("reset.daily_time") or "00:00"
    local zone  = settings.generic.get("reset.timezone")

    local hour, minute = clock:match("^(%d%d?):(%d%d)$")

    return tonumber(hour) or 0, tonumber(minute) or 0, settings.timezones[zone] or 0
end

function settings.generic.isResolved()
    return generic_resolved
end

function settings.generic.onChange(fn)
    generic_listeners[#generic_listeners + 1] = fn
end

function settings.generic.apply(payload)
    if type(payload) ~= "table" or type(payload.values) ~= "table" then return {} end

    local revision = tonumber(payload.revision)
    if revision and revision <= generic_revision then return {} end
    if revision then generic_revision = revision end

    cfg.generic = cfg.generic or {}

    local changed = {}

    for path, value in pairs(payload.values) do
        settings.write(path, value, cfg.generic)
        changed[#changed + 1] = path
    end

    generic_resolved = true

    if #changed == 0 then return changed end

    for index = 1, #generic_listeners do
        local ok, err = pcall(generic_listeners[index], changed)
        if not ok then
            logError(("Generic settings change handler failed: %s"):format(err))
        end
    end

    return changed
end

local function isFilled(value)
    return value ~= nil and value ~= ""
end

-- A dropdown can be built from something else the admin has already filled in,
-- so its choices are worked out when the editor asks rather than at boot.
local function resolveOptions(def)
    if type(def.options) ~= "function" then return def.options end

    local ok, options = pcall(def.options)

    if not ok then
        logError(("Settings '%s' options failed: %s"):format(tostring(def.path), options))

        return {}
    end

    return type(options) == "table" and options or {}
end

settings.resolveOptions = resolveOptions

-- A column inside a list or an object can carry a dynamic option set too --
-- the rider roster picks from whatever classes exist right now. Those go out
-- over NUI verbatim, so they have to be resolved here or a function reaches
-- the encoder.
local function resolveFields(fields)
    if type(fields) ~= "table" then return fields end

    local out = {}
    for index, field in ipairs(fields) do
        local copy = {}
        for key, value in pairs(field) do
            if type(value) ~= "function" then copy[key] = value end
        end
        copy.options = resolveOptions(field)
        copy.fields = resolveFields(field.fields)
        copy.item = resolveFields(field.item)
        out[index] = copy
    end
    return out
end

local function isHidden(def)
    if not def.hidden then return false end

    local ok, hidden = pcall(def.hidden)
    if not ok then
        logError(("Settings '%s' hidden check failed: %s"):format(def.path, hidden))
        return false
    end

    return hidden == true
end

function settings.describe()
    local entries = {}

    for index = 1, #settings.order do
        local path = settings.order[index]
        local def  = settings.schema[path]

        if isHidden(def) then goto continue end

        local entry = {
            path        = path,
            label       = def.label,
            help        = def.help,
            type        = def.type,
            group       = def.group,
            options     = resolveOptions(def),
            fields      = resolveFields(def.fields),
            item        = resolveFields(def.item),
            item_type   = def.item_type,
            item_default= def.item_default,
            min_items   = def.min_items,
            weight_key  = def.weight_key,
            row_fields  = def.row_fields,
            row_labels  = def.row_labels,
            takeover    = def.takeover,
            row_actions = def.row_actions,
            auto_key    = def.auto_key,
            merge_key   = def.merge_key,
            max_items   = def.max_items,
            min         = def.min,
            max         = def.max,
            max_length  = def.max_length,
            step        = def.step,
            suffix      = def.suffix,
            depends     = def.depends,
            docs        = def.docs,
            preview_from= def.preview_from,
            position_editor = def.position_editor,
            preview_model= def.preview_model,
            image_base  = def.image_base,
            min_gap     = def.min_gap,
            edit_mode   = def.edit_mode,
            live        = def.live,
            advanced    = def.advanced,
        }

        if def.type == "action" then
        elseif def.server_only then
            entry.server_only = true
            entry.stored      = isFilled(settings.read(path))
        else
            entry.default = def.default
            entry.value   = settings.read(path)
        end

        entries[#entries + 1] = entry

        ::continue::
    end

    local groups = {}
    local editors = {}
    local updates = settings.updates(settings.info.updates)

    for index = 1, #settings.group_order do
        local id = settings.group_order[index]

        if id ~= DEBUG_GROUP then
            groups[#groups + 1] = settings.groups[id]
            if settings.editors[id] then editors[#editors + 1] = settings.editors[id] end
        end
    end

    if settings.groups[DEBUG_GROUP] then groups[#groups + 1] = settings.groups[DEBUG_GROUP] end

    if updates then
        groups[#groups + 1] = { id = UPDATES_GROUP, label = "Update Log", icon = "fa-clock-rotate-left", updates = true }
    end

    return {
        resource = settings.info.id,
        label    = settings.info.label,
        icon     = settings.info.icon,
        order    = settings.info.order,
        version  = GetResourceMetadata(settings.info.id, "version", 0),
        groups   = groups,
        editors  = editors,
        updates  = updates,
        entries  = entries,
        requires = settings.info.requires,
    }
end


local FOLDER    = "transfer"
local MAX_BYTES = 2 * 1024 * 1024

local function fileFor(resource)
    local name = tostring(resource or ""):gsub("[^%w_%-]", "")

    if name == "" then return nil end

    return ("%s/%s.json"):format(FOLDER, name)
end

local function shownPath(file)
    local root = GetResourcePath(GetCurrentResourceName()) or GetCurrentResourceName()

    return (("%s/%s"):format(root, file):gsub("\\", "/"):gsub("//+", "/"))
end

local function allowed(source, resource)
    if type(resource) ~= "string" or resource == "" then return false, { _ = "malformed payload" } end

    if not Admins.canEdit(source, resource) then
        print(("^1[gg_lib] blocked settings import/export on %s from %s^0"):format(resource, Admins.actor(source)))
        return false, { _ = "you do not have permission to change this script" }
    end

    return true
end

GGCallback.register("gg_lib:settings:check", function(source, data)
    if type(data) ~= "table" or type(data.changes) ~= "table" then return false, { _ = "malformed payload" } end

    local ok, denied = allowed(source, data.resource)
    if not ok then return false, denied end

    if data.resource == GenericSettings.resource then
        return true, GenericSettings.check(data.changes)
    end

    local ran, verdict = pcall(function()
        return exports[data.resource]:ggSettingsCheck(data.changes)
    end)

    if ran and type(verdict) == "table" then return true, verdict end

    -- A script started before this gg_lib still runs the old settings module.
    local alive = pcall(function()
        return exports[data.resource]:ggSettingsPing()
    end)

    return false, { _ = alive and "restart" or "that script is not accepting settings" }
end)

GGCallback.register("gg_lib:settings:export_file", function(source, data)
    if type(data) ~= "table" or type(data.text) ~= "string" then return false, { _ = "malformed payload" } end

    local ok, denied = allowed(source, data.resource)
    if not ok then return false, denied end

    local file = fileFor(data.resource)
    if not file then return false, { _ = "malformed payload" } end

    if #data.text > MAX_BYTES then return false, { _ = "the file is too large" } end

    if not SaveResourceFile(GetCurrentResourceName(), file, data.text, -1) then
        return false, { _ = "write", path = shownPath(file) }
    end

    print(("[gg_lib] %s exported the settings of %s to %s"):format(Admins.actor(source), data.resource, file))

    return true, { path = shownPath(file) }
end)

GGCallback.register("gg_lib:settings:import_file", function(source, data)
    if type(data) ~= "table" then return false, { _ = "malformed payload" } end

    local ok, denied = allowed(source, data.resource)
    if not ok then return false, denied end

    local file = fileFor(data.resource)
    if not file then return false, { _ = "malformed payload" } end

    local text = LoadResourceFile(GetCurrentResourceName(), file)

    if type(text) ~= "string" or text == "" then
        return false, { _ = "missing", path = shownPath(file) }
    end

    if #text > MAX_BYTES then return false, { _ = "the file is too large" } end

    return true, { text = text, path = shownPath(file) }
end)

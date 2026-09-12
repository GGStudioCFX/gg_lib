
HomeFeed = HomeFeed or {}

local DEFAULT_BASE = "https://raw.githubusercontent.com/GGStudioCFX/gg_lib/main/feed"
local REFRESH_MS   = 30 * 60 * 1000
local FIRST_MS     = 5000

local current      = { source = "none" }
local fingerprints = {}
local complained   = {}

local function base()
    local override = GetConvar("gg_home_feed", "")

    return override ~= "" and override or DEFAULT_BASE
end

local function busted(address)
    return address .. (address:find("?", 1, true) and "&" or "?") .. "t=" .. tostring(os.time())
end

local function decode(body)
    if type(body) ~= "string" or body == "" then return nil end

    local ok, value = pcall(json.decode, body)

    if not ok or type(value) ~= "table" then return nil end

    return value
end

local function shaped(value, keys)
    if type(value) ~= "table" then return false end

    for index = 1, #keys do
        if value[keys[index]] ~= nil then return true end
    end

    return false
end

local HOME_KEYS    = { "promos", "ticker", "links", "featured", "version", "publishedAt" }
local PRODUCT_KEYS = { "products" }
local LOG_KEYS     = { "updates", "latest", "label" }

local function applyHome(home, source)
    current.publishedAt = home.publishedAt
    current.version     = home.version
    current.ticker      = home.ticker
    current.promos      = home.promos
    current.featured    = home.featured
    current.links       = home.links
    current.source      = source
end

local function applyLog(resource, log, source)
    current.scripts = current.scripts or {}
    current.scripts[resource] = log
    current.source = source
end

local function installed()
    local found = { gg_lib = true }

    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)

        if resource and resource ~= "gg_lib" and GetResourceState(resource) == "started" then
            local ok, alive = pcall(function()
                return exports[resource]:ggSettingsPing()
            end)

            if ok and alive == true then found[resource] = true end
        end
    end

    return found
end

local function fetch(name, done)
    local address = ("%s/%s"):format(base(), name)

    PerformHttpRequest(busted(address), function(status, body)
        local value = status == 200 and decode(body) or nil

        if not value then
            if not complained[name] then
                complained[name] = true

                print(("^3[gg_lib] feed: %s answered %s -- keeping what was showing^0"):format(name, tostring(status)))
            end

            if done then done(nil, nil) end

            return
        end

        complained[name] = nil

        if done then done(value, body) end
    end, "GET", "", { ["Cache-Control"] = "no-cache" })
end

local function changed(name, body)
    local mark = body or ""

    if fingerprints[name] == mark then return false end

    fingerprints[name] = mark

    return true
end

local RELEASES_URL = "https://api.github.com/repos/GGStudioCFX/gg_lib/releases?per_page=20"

local RELEASE_HEADERS = {
    ["User-Agent"] = "gg_lib",
    ["Accept"] = "application/vnd.github+json",
}

local function bullets(body)
    if type(body) ~= "string" then return {} end

    local out = {}

    for line in body:gmatch("[^\r\n]+") do
        local text = line:match("^%s*[%*%-]%s+(.+)$")

        if text then
            text = text:gsub("%s*by%s+@[%w%-]+%s+in%s+https?://%S+", "")
            text = text:gsub("%s*by%s+@[%w%-]+%s+in%s+#%d+", "")
            text = text:gsub("%[([^%]]+)%]%([^%)]*%)", "%1")

            -- Asterisks and backticks are markdown the page does not render, so
            -- they go. Underscores stay. Every resource is named with one, and
            -- stripping them turned "gg_lib" into "gglib" in our own release
            -- notes. Do not "fix" that by removing matching pairs either: in
            -- "gg_lib and gg_taxijob" the pair is the gap between two names, so
            -- a pair rule eats the middle and yields "gglib and ggtaxijob".
            -- A literal _emphasis_ reading as underscores is the cheaper miss.
            text = text:gsub("[%*`]", "")

            text = text:gsub("^%s+", ""):gsub("%s+$", "")

            if text ~= "" and #out < 12 then out[#out + 1] = text end
        end
    end

    return out
end

local function releaseLog(rows)
    if type(rows) ~= "table" or rows[1] == nil then return nil end

    local updates = {}

    for _, row in ipairs(rows) do
        local tag = type(row.tag_name) == "string" and (row.tag_name:gsub("^[vV]", "")) or nil

        if tag and tag ~= "" and not row.draft and not row.prerelease then
            updates[#updates + 1] = {
                version = tag,
                at      = row.published_at,
                title   = type(row.name) == "string" and row.name ~= "" and row.name ~= row.tag_name and row.name or nil,
                changes = bullets(row.body),
            }
        end
    end

    if #updates == 0 then return nil end

    return {
        label   = "gg_lib",
        latest  = updates[1].version,
        url     = "https://github.com/GGStudioCFX/gg_lib/releases",
        updates = updates,
    }
end

local function fetchReleases(done)
    PerformHttpRequest(RELEASES_URL, function(status, body)
        local rows = status == 200 and decode(body) or nil
        local log = rows and releaseLog(rows) or nil

        if not log then
            if not complained["releases"] then
                complained["releases"] = true

                print(("^3[gg_lib] releases answered %s -- keeping the log that shipped^0"):format(tostring(status)))
            end

            if done then done(nil, nil) end

            return
        end

        complained["releases"] = nil

        if done then done(log, body) end
    end, "GET", "", RELEASE_HEADERS)
end

local function publish()
    TriggerClientEvent("gg_lib:home:feed", -1, current)
end

function HomeFeed.current()
    return current
end

function HomeFeed.refresh(done)
    CreateThread(function()
        local moved = false
        local mine = installed()

        fetch("home.json", function(home, body)
            if shaped(home, HOME_KEYS) and changed("home.json", body) then
                applyHome(home, "remote")

                moved = true
            end
        end)

        fetch("products.json", function(products, body)
            if shaped(products, PRODUCT_KEYS) and changed("products.json", body) then
                current.products = products.products
                current.source   = "remote"

                moved = true
            end
        end)

        fetchReleases(function(log, body)
            if log and changed("releases", body) then
                applyLog("gg_lib", log, "remote")

                moved = true
            end
        end)

        for resource in pairs(mine) do
            if resource ~= "gg_lib" then
                fetch(("updates/%s.json"):format(resource), function(log, body)
                    if shaped(log, LOG_KEYS) and changed(resource, body) then
                        applyLog(resource, log, "remote")

                        moved = true
                    end
                end)
            end
        end

        -- Settle, not a join: one slow file must not hold up the others.
        Wait(4000)

        if moved then publish() end

        if done then done(true, moved) end
    end)
end

local function bundled(name)
    return decode(LoadResourceFile(GetCurrentResourceName(), ("feed/%s"):format(name)))
end

local function loadBundled()
    local home = bundled("home.json")

    if shaped(home, HOME_KEYS) then applyHome(home, "bundled") end

    local products = bundled("products.json")

    if shaped(products, PRODUCT_KEYS) then
        current.products = products.products
        current.source   = "bundled"
    end

    for resource in pairs(installed()) do
        if resource ~= "gg_lib" then
            local log = bundled(("updates/%s.json"):format(resource))

            if shaped(log, LOG_KEYS) then applyLog(resource, log, "bundled") end
        end
    end

    if current.source ~= "none" then publish() end
end

CreateThread(function()
    Wait(FIRST_MS)

    loadBundled()

    while true do
        HomeFeed.refresh()
        Wait(REFRESH_MS)
    end
end)

gg.daily = gg.daily or {}

local drift = 0
local nextAt = 0

local function now()
    return GetCloudTimeAsInt()
end

local function read()
    local published = GlobalState.gg_daily

    if type(published) ~= "table" then return false end

    nextAt = tonumber(published.next) or 0
    drift  = (tonumber(published.at) or now()) - now()

    return nextAt > 0
end

read()

AddStateBagChangeHandler("gg_daily", "global", function()
    read()
end)

function gg.daily.secondsUntil()
    if nextAt == 0 and not read() then return 0 end

    return math.max(0, nextAt - (now() + drift))
end

function gg.daily.nextAt()
    if nextAt == 0 then read() end

    return nextAt
end

function gg.daily.remaining()
    local left = gg.daily.secondsUntil()

    return math.floor(left / 3600), math.floor(left % 3600 / 60), math.floor(left % 60)
end

function gg.daily.clock()
    return ("%02d:%02d:%02d"):format(gg.daily.remaining())
end

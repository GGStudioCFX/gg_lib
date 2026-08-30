gg.daily = gg.daily or {}

local handlers = {}

function gg.daily.onReset(handler)
    if type(handler) ~= "function" then return false end

    handlers[#handlers + 1] = handler

    if #handlers == 1 then
        exports.gg_lib:ggDailyRegister()
    end

    return true
end

function gg.daily.secondsUntil()
    return exports.gg_lib:ggDailySecondsUntil() or 0
end

function gg.daily.nextAt()
    return exports.gg_lib:ggDailyNext() or 0
end

function gg.daily.lastAt()
    return exports.gg_lib:ggDailyLast() or 0
end

function gg.daily.force()
    return exports.gg_lib:ggDailyForce() or 0
end

exports("ggDailyRun", function(boundary)
    local failed = false

    for _, handler in ipairs(handlers) do
        local ok, result = pcall(handler, boundary)

        if not ok then
            failed = true
            gg.print.error(("A daily reset handler failed: %s"):format(result))
        elseif result == false then
            failed = true
        end
    end

    return not failed
end)

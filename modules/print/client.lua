    local printLevel = {
        error = 1,
        warn  = 2,
        info  = 3,
        debug = 4,
    }

    local levelPrefixes = {
        [printLevel.error] = "^1[ERROR]^7",
        [printLevel.warn]  = "^3[WARN]^7",
        [printLevel.info]  = "^6[INFO]^7",
        [printLevel.debug] = "^5[DEBUG]^7",
    }

    local function getDebugInfo()
        local info = debug.getinfo(4, "Sl")
        if info then
            local file = info.short_src or "unknown file"
            local line = info.currentline or "unknown line"
            return file .. ":" .. line
        end
        return "unknown location"
    end

    local function makeLogger(level)
        return function(...)
            if level == printLevel.debug and not gg.debug.on() then return end
            local dbg = getDebugInfo()
            local args = table.pack(...)
            local out = {levelPrefixes[level] or ""}
            for i = 1, args.n do
                out[#out + 1] = args[i]
            end
            out[#out + 1] = "[" .. dbg .. "]"
            print(table.unpack(out))
        end
    end

    gg.print = gg.print or {}
    gg.print.log   = makeLogger(printLevel.info)
    gg.print.warn  = makeLogger(printLevel.warn)
    gg.print.error = makeLogger(printLevel.error)
    gg.print.debug = makeLogger(printLevel.debug)

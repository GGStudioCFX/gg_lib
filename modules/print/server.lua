    local colors = {
        reset  = "\27[0m",
        blue   = "\27[34m",
        yellow = "\27[33m",
        red    = "\27[31m",
        purple = "\27[35m",
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

    local function makeLogger(tag, color, isDebug)
        return function(...)
            if isDebug and not gg.debug.on() then return end
            local dbg = getDebugInfo()
            local args = table.pack(...)
            local out = {color .. tag .. colors.reset}
            for i = 1, args.n do out[#out + 1] = args[i] end
            out[#out + 1] = "[" .. dbg .. "]"
            print(table.unpack(out))
        end
    end

    gg.print = gg.print or {}
    gg.print.log   = makeLogger("[INFO]",  colors.blue)
    gg.print.warn  = makeLogger("[WARN]",  colors.yellow)
    gg.print.error = makeLogger("[ERROR]", colors.red)
    gg.print.debug = makeLogger("[DEBUG]", colors.purple, true)

gg.cache = gg.cache or {}

gg.cache.set = function(key, value)
    gg.cache[key] = value
end

gg.cache.get = function(key)
    if gg.cache[key] then
        return gg.cache[key]
    else
        return nil -- or any default value you want
    end
end

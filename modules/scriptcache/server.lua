gg.cache = gg.cache or {}

gg.cache.set = function(key, subkey, value)
    if not subkey then
        gg.cache[key] = value
    else
        gg.cache[key] = gg.cache[key] or {}
        gg.cache[key][subkey] = value
    end
end

gg.cache.get = function(key, subkey)
    if not subkey then
        return gg.cache[key]
    else
        return gg.cache[key] and gg.cache[key][subkey] or nil
    end
end

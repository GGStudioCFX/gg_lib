gg.minigames = gg.minigames or {}

function gg.minigames.play(name, opts)
    return exports.gg_lib:ggMinigame(name, opts) == true
end

function gg.minigames.skillcheck(opts)
    return gg.minigames.play("skillcheck", opts)
end

function gg.minigames.keymash(opts)
    return gg.minigames.play("keymash", opts)
end

function gg.minigames.timing(opts)
    return gg.minigames.play("timing", opts)
end

function gg.minigames.sequence(opts)
    return gg.minigames.play("sequence", opts)
end

function gg.minigames.memory(opts)
    return gg.minigames.play("memory", opts)
end

function gg.minigames.wordwiz(opts)
    return gg.minigames.play("wordwiz", opts)
end

function gg.minigames.connect(opts)
    return gg.minigames.play("connect", opts)
end

function gg.minigames.hold(opts)
    return gg.minigames.play("hold", opts)
end

function gg.minigames.reflex(opts)
    return gg.minigames.play("reflex", opts)
end

function gg.minigames.breach(opts)
    return gg.minigames.play("breach", opts)
end

function gg.minigames.lockpick(opts)
    return gg.minigames.play("lockpick", opts)
end

function gg.minigames.codecrack(opts)
    return gg.minigames.play("codecrack", opts)
end

function gg.minigames.cancel()
    return exports.gg_lib:ggMinigameCancel()
end

function gg.minigames.active()
    return exports.gg_lib:ggMinigameActive() == true
end

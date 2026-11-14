-- Tablet apps are added and messaged from the client. The server only knows which tablet is wired,
-- and gets the same shape, every call answering false, so a shared file can name gg.tablet safely.
gg.tablet = gg.tablet or {}

local tablet   = gg.tablet
local resolved = gg.bridge.tablet

local function no() return false end

tablet.resource = resolved ~= "default" and resolved or nil
tablet.shared   = resolved == "sd-tablet" and "sd-phone" or nil

tablet.app = {
    ready     = no,
    installed = no,
    add       = function() return false, "tablet apps are added from the client" end,
    remove    = no,
    send      = no,
    drain     = function() return {} end,
}

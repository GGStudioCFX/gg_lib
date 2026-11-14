-- Runs after whichever tablet bridge installed, and after none. With no tablet every call answers
-- false (add with a reason) and drain an empty list, so a script never has to check for nil.
gg.tablet = gg.tablet or {}

local tablet = gg.tablet

local function no() return false end

if gg.bridge.tablet == "default" or type(tablet.app) ~= "table" then
    tablet.resource = nil
    tablet.shared   = nil

    tablet.app = {
        ready     = no,
        installed = no,
        add       = function() return false, "no tablet resource is running" end,
        remove    = no,
        send      = no,
        drain     = function() return {} end,
    }
end

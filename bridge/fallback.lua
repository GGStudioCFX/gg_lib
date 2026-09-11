
local function no() return false end
local function nothing() return nil end

local function noPhone()
    gg.phone = gg.phone or {}

    gg.phone.notify   = no
    gg.phone.mail     = no
    gg.phone.number   = nothing
    gg.phone.numberOf = nothing
    gg.phone.hasPhone = no
end

return {
    framework = function()
        gg.framework = gg.framework or {}

        gg.framework.GetIdentifier   = nothing
        gg.framework.GetPlayerData   = nothing
        gg.framework.GetItemData     = nothing
        gg.framework.getItemTable    = nothing
        gg.framework.GetVehicle      = function(vehicle) return vehicle end
        gg.framework.GetVehicleTable = function() return {} end
        gg.framework.getItemLabel    = function(item) return item end
    end,

    inventory = function()
        gg.inventory = gg.inventory or {}

        gg.inventory.canCarryitem     = no
        gg.inventory.hasItem          = no
        gg.inventory.addItem          = no
        gg.inventory.removeItem       = no
        gg.inventory.getItemTable     = nothing
        gg.inventory.getImageUrl      = nothing
        gg.inventory.getImageDirectory = nothing
    end,

    -- The shape of the target API. On the client init.lua wraps these in
    -- proxies that journal every call, so nothing here is ever reached there.
    target = function()
        gg.target = gg.target or {}

        gg.target.addEntity    = no
        gg.target.removeEntity = no
        gg.target.addModel     = no
        gg.target.removeModel  = no

        gg.target.addBoxZone    = nothing
        gg.target.addSphereZone = nothing
        gg.target.addPolyZone   = nothing
        gg.target.removeZone    = no

        gg.target.addGlobalPed        = no
        gg.target.removeGlobalPed     = no
        gg.target.addGlobalVehicle    = no
        gg.target.removeGlobalVehicle = no
        gg.target.addGlobalObject     = no
        gg.target.removeGlobalObject  = no
        gg.target.addGlobalPlayer     = no
        gg.target.removeGlobalPlayer  = no

        gg.target.disable  = function() end
        gg.target.isActive = no

        gg.target.AddTargetEntity    = gg.target.addEntity
        gg.target.removeTargetEntity = gg.target.removeEntity
        gg.target.AddBoxZone         = gg.target.addBoxZone
        gg.target.RemoveZone         = gg.target.removeZone
    end,

    dispatch = function()
        gg.dispatch = gg.dispatch or {}

        gg.dispatch.alert = no
    end,

    fuel = function()
        gg.fuel = gg.fuel or {}

        gg.fuel.getFuel = function(veh)
            if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return nil end

            return GetVehicleFuelLevel(veh)
        end

        gg.fuel.setFuel = function(veh, level)
            if type(veh) ~= "number" or veh == 0 or not DoesEntityExist(veh) then return false end
            if type(level) ~= "number" then level = 100.0 end

            SetVehicleFuelLevel(veh, level)

            return true
        end
    end,

    phone = noPhone,

    keys = function()
        gg.keys = gg.keys or {}

        gg.keys.AddKeys    = function() return true end
        gg.keys.RemoveKeys = no
    end,
}

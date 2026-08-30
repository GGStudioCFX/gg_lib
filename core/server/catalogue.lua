
local function itemRows()
    if not (gg.items and gg.items.list) then return {} end

    local ok, rows = pcall(gg.items.list)

    return ok and rows or {}
end

local function vehicleRows()
    if not (gg.vehicles and gg.vehicles.list) then return {} end

    local ok, rows = pcall(gg.vehicles.list)

    return ok and rows or {}
end

GGCallback.register("gg_lib:catalogue:fetch", function(source, data)
    local seeItems    = Admins.can(source, "items")
    local seeVehicles = Admins.can(source, "vehicles")

    if not seeItems and not seeVehicles then
        print(("^3[gg_lib] blocked catalogue fetch from %s^0"):format(Admins.actor(source)))
        return false
    end

    Framework.ensure()

    if type(data) == "table" and data.refresh == true then
        if gg.items and gg.items.refresh then pcall(gg.items.refresh) end
        if gg.vehicles and gg.vehicles.refresh then pcall(gg.vehicles.refresh) end
    end

    return true, {
        items     = seeItems and itemRows() or {},
        vehicles  = seeVehicles and vehicleRows() or {},
        can_give  = Admins.canEdit(source),
        image_url = GenericSettings.get("items.image_url") or "",
        wired     = { framework = gg.bridge.framework, inventory = gg.bridge.inventory },
    }
end)

GGCallback.register("gg_lib:catalogue:setImageUrl", function(source, data)
    if not Admins.can(source, "items") or not Admins.canEdit(source) then
        return false, "you do not have permission to change that"
    end

    local pattern = type(data) == "table" and data.pattern or ""

    if type(pattern) ~= "string" then return false, "malformed payload" end

    local ok, errors = GenericSettings.apply({ ["items.image_url"] = pattern }, Admins.actor(source))

    if not ok then
        return false, (type(errors) == "table" and (errors["items.image_url"] or errors._)) or "rejected"
    end

    Framework.ensure()

    if gg.items and gg.items.refresh then pcall(gg.items.refresh) end

    return true
end)

GGCallback.register("gg_lib:catalogue:giveItem", function(source, data)
    if not Admins.can(source, "items") or not Admins.canEdit(source) then
        print(("^1[gg_lib] blocked item spawn from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to spawn items"
    end

    if type(data) ~= "table" or type(data.item) ~= "string" then return false, "malformed payload" end

    Framework.ensure()

    local count = math.max(math.floor(tonumber(data.count) or 1), 1)

    if not gg.items or not gg.items.exists(data.item) then
        return false, ("'%s' is not an item on this server"):format(data.item)
    end

    if not (gg.inventory and gg.inventory.addItem) then
        return false, "no inventory is wired up"
    end

    local ok, gave = pcall(gg.inventory.addItem, source, { item = data.item, count = count })

    if not ok or gave == false then return false, "the inventory refused it, they may be full" end

    print(("[gg_lib] %s spawned %dx %s"):format(Admins.actor(source), count, data.item))

    if Logs then
        Logs.write({ {
            resource = "gg_lib",
            path     = data.item,
            action   = "item_spawn",
            new      = ("%dx %s"):format(count, data.item),
        } }, Admins.actor(source))
    end

    return true
end)

GGCallback.register("gg_lib:catalogue:spawnVehicle", function(source, data)
    if not Admins.can(source, "vehicles") or not Admins.canEdit(source) then
        print(("^1[gg_lib] blocked vehicle spawn from %s^0"):format(Admins.actor(source)))
        return false, "you do not have permission to spawn vehicles"
    end

    if type(data) ~= "table" or type(data.model) ~= "string" then return false, "malformed payload" end

    Framework.ensure()

    if gg.vehicles and gg.vehicles.ready() and not gg.vehicles.exists(data.model) then
        return false, ("'%s' is not a vehicle on this server"):format(data.model)
    end

    print(("[gg_lib] %s spawned %s"):format(Admins.actor(source), data.model))

    if Logs then
        Logs.write({ {
            resource = "gg_lib",
            path     = data.model,
            action   = "vehicle_spawn",
            new      = data.model,
        } }, Admins.actor(source))
    end

    return true
end)

gg.inventory = gg.inventory or {}

local function toNuiUrl(path)
    if type(path) ~= "string" or path == "" then return nil end

    return (path:gsub("^nui://", "https://cfx-nui-"))
end

gg.inventory.getImageUrl = function(item)
    return toNuiUrl(exports['jaksam_inventory']:getItemImagePath(item))
end

gg.inventory.getImageDirectory = function()
    return 'https://cfx-nui-jaksam_inventory/_images/'
end

gg.inventory.getItemTable = function(item)
    if not item then return exports['jaksam_inventory']:getStaticItemsList() end

    return exports['jaksam_inventory']:getStaticItem(item) or nil
end

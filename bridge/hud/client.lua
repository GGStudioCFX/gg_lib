-- How each HUD is told to hide and show, and, where it can say, whether it is
-- showing. Who is holding it hidden, the game's own HUD, the pause menu and the
-- cleanup live in modules/hud.
local providers = {
    ['0r-hud-v3'] = {
        hide = function() exports['0r-hud-v3']:ToggleVisible(false) end,
        show = function() exports['0r-hud-v3']:ToggleVisible(true) end,
    },

    ['17mov_Hud'] = {
        hide = function() exports['17mov_Hud']:ToggleDisplay(false) end,
        show = function() exports['17mov_Hud']:ToggleDisplay(true) end,
    },

    ['17mov_Interface'] = {
        hide = function() exports['17mov_Interface']:toggleDisplay(false) end,
        show = function() exports['17mov_Interface']:toggleDisplay(true) end,
    },

    ['ak47_hud'] = {
        hide    = function() exports['ak47_hud']:ToggleHudElement('all', false) end,
        show    = function() exports['ak47_hud']:ToggleHudElement('all', true) end,
        visible = function() return exports['ak47_hud']:GetHudState('all') end,
    },

    -- Its second argument would also take the minimap, which is left to native.
    ['Codem-BlackHUDV2'] = {
        hide    = function() TriggerEvent('codem-blackhudv2:SetForceHide', true, false) end,
        show    = function() TriggerEvent('codem-blackhudv2:SetForceHide', false, false) end,
        visible = function() return exports['Codem-BlackHUDV2']:IsVisible() end,
    },

    ['codem-supreme-hud'] = {
        hide    = function() exports['codem-supreme-hud']:HideHud() end,
        show    = function() exports['codem-supreme-hud']:ShowHud() end,
        visible = function() return not exports['codem-supreme-hud']:IsHudHidden() end,
    },

    ['cx-hud'] = {
        hide = function() exports['cx-hud']:hideHud() end,
        show = function() exports['cx-hud']:showHud() end,
    },

    ['dusa_hud'] = {
        hide = function() exports['dusa_hud']:HideHud() end,
        show = function() exports['dusa_hud']:ShowHud() end,
    },

    ['envi-hud'] = {
        hide = function() exports['envi-hud']:ToggleHUD(false) end,
        show = function() exports['envi-hud']:ToggleHUD(true) end,
    },

    -- Hides the whole page, and its pause menu handler leaves it hidden.
    ['esx_hud'] = {
        hide = function() exports['esx_hud']:HudToggle(false) end,
        show = function() exports['esx_hud']:HudToggle(true) end,
    },

    ['gfx-hud_aty'] = {
        hide = function() TriggerEvent('aty_hud:toggle', false) end,
        show = function() TriggerEvent('aty_hud:toggle', true) end,
    },

    ['izzy-hudv5'] = {
        hide = function() exports['izzy-hudv5']:setDisplay(false) end,
        show = function() exports['izzy-hudv5']:setDisplay(true) end,
    },

    ['izzy-hudv6'] = {
        hide = function() exports['izzy-hudv6']:setDisplay(false) end,
        show = function() exports['izzy-hudv6']:setDisplay(true) end,
    },

    ['izzy-hudv8'] = {
        hide = function() exports['izzy-hudv8']:setDisplay(false) end,
        show = function() exports['izzy-hudv8']:setDisplay(true) end,
    },

    ['jg-hud'] = {
        hide = function() exports['jg-hud']:toggleHud(false) end,
        show = function() exports['jg-hud']:toggleHud(true) end,
    },

    ['mHud'] = {
        hide = function() TriggerEvent('mHud:HideHud') end,
        show = function() TriggerEvent('mHud:ShowHud') end,
    },

    ['qs-interface'] = {
        hide = function() exports['qs-interface']:ToggleHud(false) end,
        show = function() exports['qs-interface']:ToggleHud(true) end,
    },

    -- Only the vehicle panel and minimap, and only in a vehicle. Its status
    -- panel has no way to be hidden from outside, and its own loop sends the
    -- vehicle panel again as soon as the vehicle moves.
    ['qbx_hud'] = {
        hide = function() TriggerEvent('qbx_hud:client:hideHud') end,
        show = function() TriggerEvent('qbx_hud:client:showHud') end,
    },

    ['rhud'] = {
        hide    = function() exports['rhud']:set_visible(false) end,
        show    = function() exports['rhud']:set_visible(true) end,
        visible = function() return exports['rhud']:get_visible() end,
    },

    ['tgiann-hud'] = {
        hide = function() TriggerEvent('tgiann-hud:ui', false) end,
        show = function() TriggerEvent('tgiann-hud:ui', true) end,
    },

    ['tgiann-lumihud'] = {
        hide = function() TriggerEvent('tgiann-lumihud:ui', false) end,
        show = function() TriggerEvent('tgiann-lumihud:ui', true) end,
    },

    ['vms_hud'] = {
        hide = function() exports['vms_hud']:Display(false) end,
        show = function() exports['vms_hud']:Display(true) end,
    },

    ['wais-hudv5'] = {
        hide = function() TriggerEvent('wais:hideHud', true) end,
        show = function() TriggerEvent('wais:hideHud', false) end,
    },

    ['wais-hudv6'] = {
        hide = function() exports['wais-hudv6']:hideHud() end,
        show = function() exports['wais-hudv6']:showHud() end,
    },

    -- Takes the whole interface, notifications included.
    ['ZSX_UIV2'] = {
        hide = function() exports['ZSX_UIV2']:HideInterface(true) end,
        show = function() exports['ZSX_UIV2']:HideInterface(false) end,
    },

    ['ZSX_UI'] = {
        hide = function() exports['ZSX_UI']:HideUI(true) end,
        show = function() exports['ZSX_UI']:HideUI(false) end,
    },
}

-- Its own documentation spells the folder both ways.
providers['mhud'] = providers['mHud']

return function(resource)
    local provider = providers[resource]

    if not provider then return false end

    gg.hud.resource = resource
    gg.hud.backend  = provider

    return true
end

---@class SettingsUI
SettingsUI = {}
local SettingsUI_mt = Class(SettingsUI)

function SettingsUI.new(settings)
    local self = setmetatable({}, SettingsUI_mt)
    self.settings = settings
    self.injected = false
    return self
end

function SettingsUI:inject()
    if self.injected then 
        return 
    end
    
    local page = g_gui.screenControllers[InGameMenu].pageSettings
    if not page then
        Logging.error("RHM: Settings page not found - cannot inject settings!")
        return 
    end
    
    local layout = page.generalSettingsLayout
    if not layout then
        Logging.error("RHM: Settings layout not found!")
        return 
    end
    
    -- Додаємо секцію
    local section = UIHelper.createSection(layout, "rhm_section")
    if not section then
        Logging.error("RHM: Failed to create settings section!")
        return
    end
    
    -- Додаємо складність (Multi)
    local diffOptions = {
        getTextSafe("rhm_diff_1"),
        getTextSafe("rhm_diff_2"),
        getTextSafe("rhm_diff_3")
    }
    
    local diffOpt = UIHelper.createMultiOption(
        layout,
        "rhm_diff",
        "rhm_difficulty",
        diffOptions,
        self.settings.difficulty,
        function(val)
            self.settings.difficulty = val
            self.settings:save()
        end
    )
    
    -- Додаємо HUD перемикач (Binary)
    local hudOpt = UIHelper.createBinaryOption(
        layout,
        "rhm_hud",
        "rhm_hud",
        self.settings.showHUD,
        function(val)
            self.settings.showHUD = val
            self.settings:save()
        end
    )
    
    -- Додаємо Speed Limit перемикач (Binary)
    local speedLimitOpt = UIHelper.createBinaryOption(
        layout,
        "rhm_speedlimit",
        "rhm_speedlimit",
        self.settings.enableSpeedLimit,
        function(val)
            self.settings.enableSpeedLimit = val
            self.settings:save()
            -- Logging.info("RHM: Speed Limiting %s", val and "enabled" or "disabled")
        end
    )
    
    -- Додаємо Crop Loss перемикач (Binary)
    local cropLossOpt = UIHelper.createBinaryOption(
        layout,
        "rhm_croploss",
        "rhm_croploss",
        self.settings.enableCropLoss,
        function(val)
            self.settings.enableCropLoss = val
            self.settings:save()
            -- Logging.info("RHM: Crop Loss %s", val and "enabled" or "disabled")
        end
    )
    
    self.injected = true
    -- Викликаємо invalidateLayout для правильного відображення елементів
    layout:invalidateLayout()
end

-- Допоміжна функція для безпечного отримання тексту
function getTextSafe(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        Logging.warning("RHM: Missing translation for key: " .. tostring(key))
        return key
    end
    return text
end
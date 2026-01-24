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
    
    -- Додаємо Unit System selector (Multi)
    local unitOptions = {
        g_i18n:getText("rhm_unit_metric"),
        g_i18n:getText("rhm_unit_imperial"),
        g_i18n:getText("rhm_unit_bushels")
    }
    
    local unitOpt = UIHelper.createMultiOption(
        layout,
        "rhm_units",
        "rhm_units",
        unitOptions,
        self.settings.unitSystem,
        function(val)
            self.settings.unitSystem = val
            self.settings:save()
        end
    )
    
    -- Зберігаємо посилання на UI елементи для можливості оновлення
    self.difficultyOption = diffOpt
    self.hudOption = hudOpt
    self.speedLimitOption = speedLimitOpt
    self.cropLossOption = cropLossOpt
    self.unitSystemOption = unitOpt
    
    self.injected = true
    -- Викликаємо invalidateLayout для правильного відображення елементів
    layout:invalidateLayout()
end


-- Допоміжна функція для безпечного отримання тексту
function getTextSafe(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

---Оновлює UI елементи після зміни налаштувань
function SettingsUI:refreshUI()
    if not self.injected then
        return
    end
    
    -- Оновлюємо difficulty
    if self.difficultyOption and self.difficultyOption.setState then
        self.difficultyOption:setState(self.settings.difficulty)
    end
    
    -- Оновлюємо HUD
    if self.hudOption and self.hudOption.setIsChecked then
        self.hudOption:setIsChecked(self.settings.showHUD)
    end
    
    -- Оновлюємо Speed Limit
    if self.speedLimitOption and self.speedLimitOption.setIsChecked then
        self.speedLimitOption:setIsChecked(self.settings.enableSpeedLimit)
    end
    
    -- Оновлюємо Crop Loss
    if self.cropLossOption and self.cropLossOption.setIsChecked then
        self.cropLossOption:setIsChecked(self.settings.enableCropLoss)
    end
    
    -- Оновлюємо Unit System
    if self.unitSystemOption and self.unitSystemOption.setState then
        self.unitSystemOption:setState(self.settings.unitSystem)
    end
    
    print("RHM: UI refreshed")
end

---Додає кнопку Reset в footer панель Settings меню (правильний підхід через menuButtonInfo)
function SettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then
        print("RHM: ensureResetButton - settingsFrame invalid")
        return
    end
    
    -- Створюємо кнопку тільки раз
    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,  -- X key
            text = g_i18n:getText("rhm_reset") or "Reset Settings",
            callback = function()
                print("RHM: Reset button clicked!")
                if g_realisticHarvestManager and g_realisticHarvestManager.settings then
                    g_realisticHarvestManager.settings:resetToDefaults()
                    if g_realisticHarvestManager.settingsUI then
                        g_realisticHarvestManager.settingsUI:refreshUI()
                    end
                end
            end,
            showWhenPaused = true
        }
    end
    
    -- Перевіряємо чи кнопка вже додана (уникаємо дублікатів)
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn == self._resetButton then
            print("RHM: Reset button already in menuButtonInfo")
            return
        end
    end
    
    -- Додаємо кнопку до footer панелі
    table.insert(settingsFrame.menuButtonInfo, self._resetButton)
    settingsFrame:setMenuButtonInfoDirty()
    print("RHM: Reset button added to footer! (X key)")
end

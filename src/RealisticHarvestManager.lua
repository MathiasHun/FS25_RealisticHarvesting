---@class RealisticHarvestManager
RealisticHarvestManager = {}
local RealisticHarvestManager_mt = Class(RealisticHarvestManager)

function RealisticHarvestManager.new(mission, modDirectory, modName)
    local self = setmetatable({}, RealisticHarvestManager_mt)
    
    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    
    -- Ініціалізація налаштувань
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)
    
    -- Підготовка UI
    if mission:getIsClient() and g_gui then
        self.settingsUI = SettingsUI.new(self.settings)
        
        -- Хук для створення меню
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
            self.settingsUI:inject()
        end)
    end
    
    -- Реєструємо консольні команди для налаштувань
    self.settingsGUI = SettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()
    
    -- Завантаження збережених даних при старті
    self.settings:load()
    
    -- Створюємо HUD (але НЕ ініціалізуємо елементи - це буде в load())
    if mission:getIsClient() then
        self.hud = HUD.new(self.settings, g_currentMission.hud.speedMeter, self.modDirectory)
        
        if not self.hud then
            Logging.error("RHM: Failed to create HUD instance!")
        end
    end
    
    return self
end

-- Викликається після завантаження місії
function RealisticHarvestManager:onMissionLoaded()
    if self.hud then
        self.hud:load()
    end
end

-- Викликається кожен кадр
function RealisticHarvestManager:update(dt)
    -- Оновлюємо HUD якщо він існує та є активний комбайн
    if self.hud and g_currentMission.controlledVehicle then
        local vehicle = g_currentMission.controlledVehicle
        
        -- Перевіряємо чи це комбайн з нашою спеціалізацією
        if vehicle.spec_rhm_Combine then
            -- Встановлюємо активний комбайн
            self.hud:setVehicle(vehicle)
            
            -- Оновлюємо дані HUD
            self.hud:update(dt)
        else
            -- Скидаємо комбайн якщо не активний
            self.hud:setVehicle(nil)
        end
    end
end

function RealisticHarvestManager:delete()
    -- Очистка HUD
    if self.hud then
        self.hud:delete()
        self.hud = nil
    end
end
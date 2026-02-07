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
        
        -- Hook for menu creation (INSTANCE HOOK to avoid conflicts)
        local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
        if settingsPage then
            settingsPage.onFrameOpen = Utils.appendedFunction(settingsPage.onFrameOpen, function()
                self.settingsUI:inject()
            end)
            
            -- Hook for footer buttons (reset)
            settingsPage.updateButtons = Utils.appendedFunction(settingsPage.updateButtons, function(frame)
                if self.settingsUI then
                    self.settingsUI:ensureResetButton(frame)
                end
            end)
        else
            Logging.error("RHM: InGameMenuSettingsFrame (pageSettings) not found!")
        end
        

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

-- Рекурсивно шукає vehicle з rhm_Combine spec в ієрархії
local function findCombineInHierarchy(vehicle, checkedVehicles)
    if not vehicle then
        return nil
    end
    
    -- Запобігаємо нескінченній рекурсії
    checkedVehicles = checkedVehicles or {}
    if checkedVehicles[vehicle] then
        return nil
    end
    checkedVehicles[vehicle] = true
    
    -- Перевіряємо поточний vehicle
    if vehicle.spec_rhm_Combine then
        return vehicle
    end
    
    -- Перевіряємо rootVehicle
    if vehicle.rootVehicle and not checkedVehicles[vehicle.rootVehicle] then
        local found = findCombineInHierarchy(vehicle.rootVehicle, checkedVehicles)
        if found then return found end
    end
    
    -- Перевіряємо attacherVehicle (parent)
    if vehicle.attacherVehicle and not checkedVehicles[vehicle.attacherVehicle] then
        local found = findCombineInHierarchy(vehicle.attacherVehicle, checkedVehicles)
        if found then return found end
    end
    
    -- Перевіряємо всі attached vehicles (children)
    if vehicle.getAttachedImplements then
        local implements = vehicle:getAttachedImplements()
        if implements then
            for _, implement in ipairs(implements) do
                if implement.object and not checkedVehicles[implement.object] then
                    local found = findCombineInHierarchy(implement.object, checkedVehicles)
                    if found then return found end
                end
            end
        end
    end
    
    return nil
end

-- Викликається кожен кадр
-- Helper: Find the actual vehicle the player is controlling
function RealisticHarvestManager:getControlledVehicle()
    -- 1. Check standard game function
    local vehicle = g_currentMission.controlledVehicle
    if vehicle then return vehicle end
    
    -- 2. Check local player's current vehicle (fallback)
    if g_localPlayer and g_localPlayer:getCurrentVehicle() then
        return g_localPlayer:getCurrentVehicle()
    end
    
    -- 3. Iterate entered vehicles (extreme fallback)
    if g_currentMission.vehicles then
        for _, v in pairs(g_currentMission.vehicles) do
            if v.getIsEntered and v:getIsEntered() then
                return v
            end
        end
    end
    
    return nil
end

-- Викликається кожен кадр
function RealisticHarvestManager:update(dt)
    -- Оновлюємо HUD якщо він існує
    if self.hud then
        -- Знаходимо, де зараз гравець
        local vehicle = self:getControlledVehicle()
        local combineVehicle = nil
        
        if vehicle then
            -- Для модульних систем (Nexat) шукаємо з rootVehicle
            local searchRoot = vehicle.rootVehicle or vehicle
            
            -- Шукаємо комбайн у всій ієрархії (для Nexat та інших модульних систем)
            combineVehicle = findCombineInHierarchy(searchRoot)
        end
        
        -- Зберігаємо на майбутнє для draw()
        self.lastActiveCombine = combineVehicle
        
        if combineVehicle and combineVehicle:getIsTurnedOn() then
            -- Встановлюємо активний комбайн
            self.hud:setVehicle(combineVehicle)
            
            -- Оновлюємо дані HUD
            self.hud:update(dt)
        else
            -- Скидаємо комбайн якщо не активний
            self.hud:setVehicle(nil)
        end
    end
end

-- Викликається кожен кадр для МАЛЮВАННЯ HUD
function RealisticHarvestManager:draw()
    -- НЕ малюємо якщо відкрито меню/GUI
    if g_gui:getIsGuiVisible() then
        return
    end
    
    -- Перевіряємо чи є активний комбайн
    local combineVehicle = self.lastActiveCombine
    
    -- Також перевіряємо чи гравець все ще в техніці (щоб HUD зникав при виході)
    local playerVehicle = self:getControlledVehicle()
    if not playerVehicle then
        return
    end
    
    -- Малюємо HUD якщо є активний комбайн і він увімкнений
    if self.hud and combineVehicle and combineVehicle:getIsTurnedOn() then
        if self.settings and self.settings.showHUD then
            self.hud:draw()
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
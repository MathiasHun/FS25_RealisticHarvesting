---@class Settings
-- Система налаштувань для Realistic Harvest Manager
Settings = {}
local Settings_mt = Class(Settings)

-- Константи рівнів складності (як у CombineXP)
Settings.DIFFICULTY_ARCADE = 1
Settings.DIFFICULTY_NORMAL = 2
Settings.DIFFICULTY_REALISTIC = 3

-- Power boost values (з CombineXP)
Settings.POWER_BOOST_ARCADE = 100     -- 100% boost → maxLoad = 200%
Settings.POWER_BOOST_NORMAL = 20      -- 20% boost → maxLoad = 120%
Settings.POWER_BOOST_REALISTIC = 0    -- 0% boost → maxLoad = 100%

function Settings.new(manager)
    local self = setmetatable({}, Settings_mt)
    self.manager = manager
    
    -- Difficulty settings
    self.difficulty = Settings.DIFFICULTY_NORMAL -- Normal за замовчуванням
    
    -- Feature toggles
    self.enableSpeedLimit = true
    self.enableCropLoss = false
    self.showHUD = true
    
    -- HUD settings
    self.hudOffsetX = 0  -- Горизонтальне зміщення (-200 to 200)
    self.hudOffsetY = 350  -- Вертикальне зміщення (100 to 500)
    
    Logging.info("RHM: Settings initialized with difficulty: Normal")
    
    return self
end

---Отримує поточний power boost залежно від складності
---@return number Power boost (0-100)
function Settings:getPowerBoost()
    if self.difficulty == Settings.DIFFICULTY_ARCADE then
        return Settings.POWER_BOOST_ARCADE
    elseif self.difficulty == Settings.DIFFICULTY_REALISTIC then
        return Settings.POWER_BOOST_REALISTIC
    else
        return Settings.POWER_BOOST_NORMAL
    end
end

---Отримує множник втрат залежно від складності
---@return number Loss multiplier
function Settings:getLossMultiplier()
    if self.difficulty == Settings.DIFFICULTY_ARCADE then
        return 0.5 -- Менші втрати
    elseif self.difficulty == Settings.DIFFICULTY_REALISTIC then
        return 2.0 -- Більші втрати
    else
        return 1.0 -- Нормальні втрати
    end
end

---Встановлює рівень складності
---@param difficulty number Рівень складності (1-3)
function Settings:setDifficulty(difficulty)
    if difficulty >= Settings.DIFFICULTY_ARCADE and difficulty <= Settings.DIFFICULTY_REALISTIC then
        self.difficulty = difficulty
        
        local difficultyName = "Normal"
        if difficulty == Settings.DIFFICULTY_ARCADE then
            difficultyName = "Arcade"
        elseif difficulty == Settings.DIFFICULTY_REALISTIC then
            difficultyName = "Realistic"
        end
        
        Logging.info("RHM: Difficulty changed to: %s (powerBoost: %d%%)", 
            difficultyName, self:getPowerBoost())
    end
end

---Отримує назву поточного рівня складності
---@return string Назва рівня
function Settings:getDifficultyName()
    if self.difficulty == Settings.DIFFICULTY_ARCADE then
        return "Arcade"
    elseif self.difficulty == Settings.DIFFICULTY_REALISTIC then
        return "Realistic"
    else
        return "Normal"
    end
end

---Завантажує налаштування
function Settings:load()
    -- Перевіряємо що difficulty це число
    if type(self.difficulty) ~= "number" then
        Logging.warning("RHM: difficulty is not a number! Type: %s, Value: %s", 
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL -- fallback
    end
    
    self.manager:loadSettings(self)
    Logging.info("RHM: Settings Loaded. Difficulty: %s, HUD: %s", 
        self:getDifficultyName(), tostring(self.showHUD))
end

---Зберігає налаштування
function Settings:save()
    -- Перевіряємо що difficulty це число
    if type(self.difficulty) ~= "number" then
        Logging.warning("RHM: difficulty is not a number! Type: %s, Value: %s", 
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL -- fallback
    end
    
    self.manager:saveSettings(self)
    -- Logging.info("RHM: Settings Saved. Difficulty: %s, HUD: %s", 
    --    self:getDifficultyName(), tostring(self.showHUD))
end

---Скидання налаштувань до значень за замовчуванням
function Settings:resetToDefaults()
    self.difficulty = Settings.DIFFICULTY_NORMAL
    self.enableSpeedLimit = true
    self.enableCropLoss = true
    self.showHUD = true
    self.hudOffsetX = 0
    self.hudOffsetY = 350
    
    -- Зберігаємо
    self:save()
    
    print("RHM: Settings reset to defaults")
end

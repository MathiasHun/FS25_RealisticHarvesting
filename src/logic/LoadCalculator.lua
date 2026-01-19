---@class LoadCalculator
-- Розраховує навантаження на двигун комбайна
-- Базується на логіці CombineXP, але з покращеннями
LoadCalculator = {}
local LoadCalculator_mt = Class(LoadCalculator)

function LoadCalculator.new(modDirectory)
    local self = setmetatable({}, LoadCalculator_mt)
    
    self.debug = false
    self.modDirectory = modDirectory  -- Зберігаємо modDirectory
    
    -- Коефіцієнти складності культур (завантажуються з XML)
    self.CROP_FACTORS = {}
    self:loadCropFactorsFromXML()
    
    -- Дані для розрахунку середнього навантаження (як у CombineXP)
    self.totalDistance = 0
    self.totalArea = 0
    self.currentTime = 0
    self.avgTime = 1500  -- 1.5 секунди між вимірами
    self.distanceForMeasuring = 3  -- 3 метри
    
    -- Базова продуктивність (буде встановлена в onLoad)
    self.basePerfAvgArea = 0  -- м² на секунду
    self.currentAvgArea = 0
    
    -- Поточне навантаження
    self.engineLoad = 0
    
    -- Обмеження швидкості (як у CombineXP)
    self.speedLimit = 15  -- Поточний ліміт швидкості в км/год
    self.genuineSpeedLimit = 15  -- Оригінальний ліміт швидкості комбайна
    
    -- Crop loss and productivity
    self.cropLoss = 0  -- Поточні втрати врожаю (%)
    self.tonPerHour = 0  -- Продуктивність в T/h
    self.totalOutputMass = 0  -- Загальна маса зібраного врожаю
    
    print("RHM: LoadCalculator initialized")
    
    return self
end

---Завантажує коефіцієнти культур з XML файлу
function LoadCalculator:loadCropFactorsFromXML()
    if not self.modDirectory then
        print("RHM: WARNING - modDirectory not provided to LoadCalculator")
        self:loadDefaultCropFactors()
        return
    end
    
    -- Використовуємо Utils.getFilename для правильного шляху
    local xmlPath = Utils.getFilename("data/fruitTypes.xml", self.modDirectory)
    
    local xmlFile = XMLFile.load("RHM_FruitTypes", xmlPath)
    if not xmlFile then
        print("RHM: WARNING - Could not load fruitTypes.xml from: " .. tostring(xmlPath))
        print("RHM: Falling back to default crop factors")
        self:loadDefaultCropFactors()
        return
    end
    
    local i = 0
    while true do
        local key = string.format("fruitTypes.fruitType(%d)", i)
        if not xmlFile:hasProperty(key) then
            break
        end
        
        local fruitName = xmlFile:getString(key .. "#name")
        local factor = xmlFile:getFloat(key .. "#mrMaterialQtyFx", 1.0)
        
        if fruitName then
            -- Знайти FruitType ID за ім'ям
            local fruitTypeIndex = g_fruitTypeManager:getFruitTypeIndexByName(fruitName)
            if fruitTypeIndex then
                self.CROP_FACTORS[fruitTypeIndex] = factor
                if self.debug then
                    print(string.format("RHM: Loaded crop factor for %s: %.2f", fruitName, factor))
                end
            end
        end
        
        i = i + 1
    end
    
    xmlFile:delete()
    print(string.format("RHM: Loaded %d crop factors from fruitTypes.xml", i))
end

---Завантажує crop factors за замовчуванням
function LoadCalculator:loadDefaultCropFactors()
    -- Fallback до базових значень
    self.CROP_FACTORS[FruitType.WHEAT] = 1.0
    self.CROP_FACTORS[FruitType.BARLEY] = 1.05
    self.CROP_FACTORS[FruitType.MAIZE] = 1.8
end

---Встановлює базову продуктивність комбайна
---@param basePerf number Базова продуктивність в га/год
function LoadCalculator:setBasePerformance(basePerf)
    -- Конвертуємо га/год в м²/с (як у CombineXP)
    self.basePerfAvgArea = basePerf / 36
    
    if self.debug then
        print(string.format("RHM: Base performance set to %.1f ha/h (%.2f m²/s)", 
            basePerf, self.basePerfAvgArea))
    end
end

---Отримує базову продуктивність з потужності двигуна
---@param vehicle table Комбайн
---@return number Базова продуктивність в га/год
function LoadCalculator:getBasePerformanceFromPower(vehicle)
    local coef = 1.2  -- Коефіцієнт як у CombineXP
    local power = 0
    
    -- Спробувати отримати потужність з motorized spec
    if vehicle.spec_motorized and vehicle.spec_motorized.motor then
        power = vehicle.spec_motorized.motor.maxPower  -- в кВт
        if power and power > 0 then
            local basePerf = power * coef
            if self.debug then
                print(string.format("RHM: Computed basePerf from motor power: %.1f kW => %.1f ha/h", 
                    power, basePerf))
            end
            return basePerf
        end
    end
    
    -- Fallback: використати дані з XML
    if vehicle.xmlFile then
        local key = "vehicle.storeData.specs.power"
        local specsPower = vehicle.xmlFile:getValue(key)
        if specsPower and tonumber(specsPower) > 0 then
            local basePerf = tonumber(specsPower) * coef
            if self.debug then
                print(string.format("RHM: Computed basePerf from specs power: %.1f => %.1f ha/h", 
                    specsPower, basePerf))
            end
            return basePerf
        end
    end
    
    -- Якщо нічого не знайшли, використати значення за замовчуванням
    print("RHM: Warning - Could not determine combine power, using default basePerf")
    return 100  -- Значення за замовчуванням
end

---Оновлює дані для розрахунку навантаження
---@param vehicle table Комбайн
---@param dt number Delta time в мс
---@param area number Площа що була зібрана
function LoadCalculator:update(vehicle, dt, area)
    -- Оновлюємо відстань
    self.totalDistance = self.totalDistance + vehicle.lastMovedDistance
    
    -- Оновлюємо площу
    self.totalArea = self.totalArea + area
    
    -- Оновлюємо час
    self.currentTime = self.currentTime + dt
    
    -- Перевіряємо чи час для нового виміру (як у CombineXP)
    if self.currentTime > self.avgTime or self.totalDistance > self.distanceForMeasuring then
        self:calculateEngineLoad(vehicle)
        self:calculateSpeedLimit(vehicle)
        
        -- Скидаємо лічильники
        self.currentTime = 0
        self.totalArea = 0
        self.totalDistance = 0
    end
end

---Розраховує навантаження на двигун
---@param vehicle table Комбайн
function LoadCalculator:calculateEngineLoad(vehicle)
    if self.currentTime <= 0 then
        return
    end
    
    -- Отримуємо коефіцієнт культури
    local cropFactor = 1.0
    local spec_combine = vehicle.spec_combine
    if spec_combine and spec_combine.lastValidInputFruitType then
        cropFactor = self.CROP_FACTORS[spec_combine.lastValidInputFruitType] or 1.0
    end
    
    -- Розраховуємо середню площу за секунду (як у CombineXP)
    -- 500 = 1000 / 2, де 2 - це коефіцієнт для врахування добрив
    local avgArea = 500 * self.totalArea * cropFactor * g_currentMission:getFruitPixelsToSqm() / self.currentTime
    
    -- Згладжування (як у CombineXP)
    if self.currentAvgArea > (0.75 * self.basePerfAvgArea) then
        avgArea = 0.5 * self.currentAvgArea + 0.5 * avgArea
    end
    
    self.currentAvgArea = avgArea
    
    -- Отримуємо power boost для розрахунку навантаження
    local powerBoost = 0
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        powerBoost = g_realisticHarvestManager.settings:getPowerBoost()
    end
    
    -- Максимальна допустима площа з урахуванням power boost
    local maxAvgArea = (1 + 0.01 * powerBoost) * self.basePerfAvgArea
    
    -- Розраховуємо навантаження відносно maxAvgArea (з урахуванням boost!)
    -- Це важливо щоб HUD показував правильне навантаження
    if maxAvgArea > 0 then
        self.engineLoad = self.currentAvgArea / maxAvgArea
    else
        self.engineLoad = 0
    end
    
    if self.debug then
        print(string.format("RHM: Engine load calculated: %.1f%% (avgArea: %.2f, basePerf: %.2f)", 
            self.engineLoad * 100, self.currentAvgArea, self.basePerfAvgArea))
    end
end

---Розраховує обмеження швидкості (як у CombineXP)
---@param vehicle table Комбайн
function LoadCalculator:calculateSpeedLimit(vehicle)
    if self.currentAvgArea == 0 then
        self.speedLimit = self.genuineSpeedLimit
        return
    end
    
    -- Отримуємо поточну швидкість
    local avgSpeed = 1000 * self.totalDistance / self.currentTime  -- м/с
    
    -- Отримуємо power boost з налаштувань (як у CombineXP)
    local powerBoost = 0
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        powerBoost = g_realisticHarvestManager.settings:getPowerBoost()
    end
    
    -- Максимальна допустима площа з урахуванням power boost (як у CombineXP)
    -- Формула: maxAvgArea = (1 + 0.01 * powerBoost) * basePerfAvgArea
    local maxAvgArea = (1 + 0.01 * powerBoost) * self.basePerfAvgArea
    
    -- Діагностика
    Logging.info("RHM: [LoadCalc] currentAvgArea: %.2f, maxAvgArea: %.2f, ratio: %.1f%%", 
        self.currentAvgArea, maxAvgArea, (self.currentAvgArea / maxAvgArea) * 100)
    
    -- Розраховуємо прискорення площі (як у CombineXP)
    local areaAcc = (self.currentAvgArea - self.basePerfAvgArea) / self.currentTime
    
    local predictLimitSet = false
    
    -- Передбачення (якщо навантаження зростає)
    if areaAcc > 0 then
        local predictAvgArea = self.currentAvgArea + areaAcc * 3000  -- Передбачення на 3 секунди
        if predictAvgArea > 1.5 * maxAvgArea then
            -- Різко зменшити швидкість
            local oldLimit = self.speedLimit
            self.speedLimit = math.max(2, math.min(0.95 * self.speedLimit, 0.9 * avgSpeed * 3.6))
            predictLimitSet = true
            Logging.info("RHM: [LoadCalc] PREDICT OVERLOAD - reducing speed %.1f -> %.1f km/h", 
                oldLimit, self.speedLimit)
        end
    end
    
    if not predictLimitSet then
        -- ФІНАЛЬНА АГРЕСИВНА ЛОГІКА:
        -- >90% → зменшити швидкість (високе навантаження)
        -- 60-90% → тримати поточну (широка стабільна зона)
        -- <60% → збільшити (великий запас)
        
        if self.currentAvgArea > (0.90 * maxAvgArea) then
            -- Високе навантаження - зменшити швидкість
            local oldLimit = self.speedLimit
            self.speedLimit = math.max(2, math.min(self.speedLimit, avgSpeed * 3.6) - 10 * (1 - maxAvgArea / self.currentAvgArea)^2)
            if oldLimit ~= self.speedLimit then
                Logging.info("RHM: [LoadCalc] HIGH LOAD (%.1f%%) - reducing speed %.1f -> %.1f km/h", 
                    (self.currentAvgArea / maxAvgArea) * 100, oldLimit, self.speedLimit)
            end
        elseif self.currentAvgArea < (0.60 * maxAvgArea) then
            -- Є великий запас - збільшити швидкість
            local oldLimit = self.speedLimit
            self.speedLimit = math.min(self.genuineSpeedLimit, self.speedLimit + 0.1 * (maxAvgArea / self.currentAvgArea)^3)
            if oldLimit ~= self.speedLimit then
                Logging.info("RHM: [LoadCalc] Capacity available (%.1f%%) - increasing speed %.1f -> %.1f km/h", 
                    (self.currentAvgArea / maxAvgArea) * 100, oldLimit, self.speedLimit)
            end
        end
    end
end

---Отримує поточне навантаження на двигун
---@return number Навантаження в відсотках (0-100+)
function LoadCalculator:getEngineLoad()
    return self.engineLoad * 100
end

---Отримує поточне обмеження швидкості
---@return number Обмеження швидкості в км/год
function LoadCalculator:getSpeedLimit()
    return self.speedLimit
end

---Встановлює оригінальне обмеження швидкості комбайна
---@param limit number Оригінальний ліміт в км/год
function LoadCalculator:setGenuineSpeedLimit(limit)
    self.genuineSpeedLimit = limit
    self.speedLimit = limit
end

---Скидає всі дані
function LoadCalculator:reset()
    self.totalDistance = 0
    self.totalArea = 0
    self.currentTime = 0
    self.currentAvgArea = 0
    self.engineLoad = 0
    self.cropLoss = 0
    -- Скидаємо speedLimit до genuineSpeedLimit (коли не косимо)
    self.speedLimit = self.genuineSpeedLimit
    
    if self.debug then
        print("RHM: LoadCalculator reset")
    end
end

---Розраховує втрати врожаю при перевантаженні
---@return number Втрати в відсотках (0-50)
function LoadCalculator:calculateCropLoss()
    -- Перевіряємо чи увімкнені втрати
    if not g_realisticHarvestManager or not g_realisticHarvestManager.settings then
        return 0
    end
    
    if not g_realisticHarvestManager.settings.enableCropLoss then
        return 0
    end
    
    -- Якщо навантаження > 100%, розраховуємо втрати
    if self.engineLoad > 1.0 then
        local overload = self.engineLoad - 1.0 -- 0.0 - 1.0+
        
        -- Отримуємо множник втрат залежно від складності
        local lossMultiplier = g_realisticHarvestManager.settings:getLossMultiplier()
        
        -- Формула втрат: overload^2 * multiplier * 100
        -- Наприклад: 150% load → 50% overload → 12.5% втрат (Normal)
        --             150% load → 50% overload → 6.25% втрат (Arcade)
        --             150% load → 50% overload → 25% втрат (Realistic)
        local loss = (overload^2) * lossMultiplier * 100
        
        self.cropLoss = math.min(loss, 50) -- Максимум 50% втрат
    else
        self.cropLoss = 0
    end
    
    return self.cropLoss
end

---Отримує поточні втрати врожаю
---@return number Втрати в відсотках (0-50)
function LoadCalculator:getCropLoss()
    return self.cropLoss
end

---Отримує продуктивність в тоннах на годину
---@return number Продуктивність в T/h
function LoadCalculator:getTonPerHour()
    return self.tonPerHour
end

---Оновлює продуктивність на основі зібраної маси
---@param mass number Маса зібраного врожаю в кг
---@param dt number Delta time в мс
function LoadCalculator:updateProductivity(mass, dt)
    self.totalOutputMass = self.totalOutputMass + mass
    
    -- Розраховуємо T/h
    if dt > 0 then
        -- kg/ms → T/h
        self.tonPerHour = (mass / dt) * 3600 / 1000
    end
end


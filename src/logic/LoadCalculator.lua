---@class LoadCalculator
-- Розраховує навантаження на двигун комбайна
LoadCalculator = {}
local LoadCalculator_mt = Class(LoadCalculator)

function LoadCalculator.new(modDirectory)
    local self = setmetatable({}, LoadCalculator_mt)
    
    self.debug = false
    self.modDirectory = modDirectory or g_currentModDirectory  -- Зберігаємо modDirectory (with fallback)
    
    -- Коефіцієнти складності культур (завантажуються з XML)
    self.CROP_FACTORS = {}
    self:loadCropFactorsFromXML()
    
    -- Дані для розрахунку середнього навантаження
    self.totalDistance = 0
    self.totalArea = 0
    self.currentTime = 0
    self.avgTime = 1500  -- 1.5 секунди між вимірами
    self.distanceForMeasuring = 3  -- 3 метри
    
    -- Базова продуктивність (буде встановлена в onLoad)
    self.basePerfAvgArea = 0  -- м² на секунду
    self.currentAvgArea = 0
    self.lastAvgArea = 0  -- Попереднє середнє (для розрахунку прискорення)
    self.rawAvgArea = 0  -- Сире (незгладжене) значення для аварійного гальмування
    
    -- Поточне навантаження
    self.engineLoad = 0
    self.speedLimit = 15  -- Поточний ліміт швидкості (км/год)
    self.genuineSpeedLimit = 15  -- Оригінальний ліміт з гри
    self.workingSpeedLimit = 0  -- Робочий ліміт (зберігається між сесіями збирання)
    self.lastCropType = nil  -- Остання культура (для детекції зміни)
    self.lastHarvestTime = 0  -- Час останнього збирання (для детекції тривалої паузи)
    
    -- Crop loss and productivity
    self.cropLoss = 0  -- Поточні втрати врожаю (%)
    self.tonPerHour = 0  -- Продуктивність в T/h
    self.totalOutputMass = 0  -- Загальна маса зібраного врожаю
    
    -- Накопичення для розрахунку T/h
    self.productivityMass = 0  -- Накопичена маса за поточний період (кг)
    self.productivityTime = 0  -- Час накопичення (мс)
    self.productivityUpdateInterval = 3000  -- Оновлювати кожні 3 секунди
    
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
    -- Конвертуємо га/год в м²/с 
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
    local coef = 1.2  -- Стандартний коефіцієнт для зернозбиральних комбайнів
    local power = 0
    
    -- Визначаємо тип техніки за категорією
    local keyCategory = "vehicle.storeData.category"
    local category = vehicle.xmlFile:getValue(keyCategory)
    
    if category == "forageHarvesters" or category == "forageHarvesterCutters" then
        coef = 12.0  -- Кормозбиральні комбайни обробляють набагато більше матеріалу
    elseif category == "beetVehicles" or category == "beetHarvesting" then
        coef = 0.6  -- Бурякозбиральні комбайни
    elseif category == "potatoVehicles" then
        coef = 0.3  -- Картоплезбиральні комбайни
    end
    
    -- Спробувати отримати потужність з motorized spec
    if vehicle.spec_motorized and vehicle.spec_motorized.motor then
        power = vehicle.spec_motorized.motor.hp or 0
    end
    
    -- Якщо не знайшли, спробувати з XML
    if power == 0 then
        local key, motorId = ConfigurationUtil.getXMLConfigurationKey(
            vehicle.xmlFile, 
            vehicle.configurations.motor, 
            "vehicle.motorized.motorConfigurations.motorConfiguration", 
            "vehicle.motorized", 
            "motor"
        )
        local fallbackConfigKey = "vehicle.motorized.motorConfigurations.motorConfiguration(0)"
        local fallbackOldKey = "vehicle"
        
        if SpecializationUtil.hasSpecialization(Motorized, vehicle.specializations) then
            power = ConfigurationUtil.getConfigurationValue(
                vehicle.xmlFile, key, "", "#hp", nil, fallbackConfigKey, fallbackOldKey
            )
        end
    end
    
    if power and tonumber(power) > 0 then
        local basePerf = tonumber(power) * coef
        print(string.format("RHM: BasePerf computed for %s (category: %s, coef: %.1f): %d hp × %.1f = %.1f ha/h", 
            vehicle:getFullName(), category or "unknown", coef, power, coef, basePerf))
        return basePerf
    end
    
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
    
    -- Перевіряємо чи час для нового виміру
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
    
    -- Розраховуємо RAW середню площу за секунду (без згладжування)
    -- 500 = 1000 / 2, де 2 - це коефіцієнт для врахування добрив
    local rawAvgArea = 500 * self.totalArea * cropFactor * g_currentMission:getFruitPixelsToSqm() / self.currentTime
    
    -- ADAPTIVE SMOOTHING: більше згладжування при високому навантаженні
    local loadRatio = self.currentAvgArea / math.max(0.01, self.basePerfAvgArea)
    local smoothFactor = 0.3 + 0.4 * math.min(1.0, loadRatio)
    smoothFactor = math.min(0.7, smoothFactor)  -- Max 70% smoothing
    
    -- Застосовуємо згладжування тільки якщо є попереднє значення
    local avgArea = rawAvgArea
    if self.currentAvgArea > (0.75 * self.basePerfAvgArea) then
        avgArea = (1 - smoothFactor) * rawAvgArea + smoothFactor * self.currentAvgArea
    end
    
    -- Зберігаємо обидва значення для різних цілей
    self.lastAvgArea = self.currentAvgArea
    self.currentAvgArea = avgArea
    self.rawAvgArea = rawAvgArea  -- Для аварійного гальмування
    
    -- Отримуємо power boost для розрахунку навантаження
    local powerBoost = 0
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        powerBoost = g_realisticHarvestManager.settings:getPowerBoost()
    end
    
    -- Максимальна допустима площа з урахуванням power boost
    local maxAvgArea = (1 + 0.01 * powerBoost) * self.basePerfAvgArea
    
    -- Розраховуємо навантаження відносно maxAvgArea
    if maxAvgArea > 0 then
        self.engineLoad = self.currentAvgArea / maxAvgArea
    else
        self.engineLoad = 0
    end
    
    if self.debug then
        print(string.format("RHM: Load: %.1f%% (Raw: %.2f, Smooth: %.2f, SmoothFactor: %.2f)", 
            self.engineLoad * 100, rawAvgArea, self.currentAvgArea, smoothFactor))
    end
end

---Розраховує обмеження швидкості
---@param vehicle table Комбайн
function LoadCalculator:calculateSpeedLimit(vehicle)
    -- Якщо не збираємо врожай (area = 0), не обмежуємо швидкість
    if self.currentAvgArea == 0 then
        -- Зберігаємо поточний робочий ліміт перед скиданням
        if self.speedLimit < self.genuineSpeedLimit then
            self.workingSpeedLimit = self.speedLimit
        end
        self.speedLimit = self.genuineSpeedLimit
        return
    end
    
    -- Детекція зміни культури або тривалої паузи
    local currentCropType = nil
    local spec_combine = vehicle.spec_combine
    if spec_combine and spec_combine.lastValidInputFruitType then
        currentCropType = spec_combine.lastValidInputFruitType
    end
    
    local currentTime = g_currentMission.time or 0
    local timeSinceLastHarvest = currentTime - self.lastHarvestTime
    
    -- Скидаємо workingSpeedLimit якщо:
    -- 1. Змінилась культура
    -- 2. Пройшло >30 секунд без збирання (переїхали на інше поле)
    if (currentCropType and self.lastCropType and currentCropType ~= self.lastCropType) or
       (timeSinceLastHarvest > 30000) then
        self.workingSpeedLimit = 0  -- Скидаємо, почнемо з 7 км/год
    end
    
    self.lastCropType = currentCropType
    self.lastHarvestTime = currentTime
    
    -- CONSERVATIVE START: При першому заході в культуру встановлюємо безпечний ліміт
    -- Якщо є збережений робочий ліміт - використовуємо його, інакше - консервативний старт
    if self.speedLimit == self.genuineSpeedLimit then
        if self.workingSpeedLimit > 0 and self.workingSpeedLimit < 12 then
            -- Відновлюємо попередній робочий ліміт
            self.speedLimit = self.workingSpeedLimit
        else
            -- Перший раз за сесію - консервативний старт
            self.speedLimit = 7.0
            self.workingSpeedLimit = 7.0
        end
    end
    
    -- Отримуємо поточну швидкість
    local avgSpeed = 1000 * self.totalDistance / self.currentTime  -- м/с
    
    -- Отримуємо power boost
    local powerBoost = 0
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        powerBoost = g_realisticHarvestManager.settings:getPowerBoost()
    end
    
    local maxAvgArea = (1 + 0.01 * powerBoost) * self.basePerfAvgArea
    
    -- Розраховуємо прискорення (derivative of smoothed value)
    local areaAcc = 0
    if self.currentTime > 0 and self.lastAvgArea > 0 then
        areaAcc = (self.currentAvgArea - self.lastAvgArea) / self.currentTime
    end
    
    -- === THREE-ZONE CONTROL SYSTEM ===
    local loadRatio = self.currentAvgArea / maxAvgArea
    local rawLoadRatio = (self.rawAvgArea or self.currentAvgArea) / maxAvgArea
    local newSpeedLimit = self.speedLimit
    local controlZone = "HOLD"
    
    -- === GRADUATED EMERGENCY BRAKE SYSTEM ===
    -- Чим вище навантаження, тим агресивніше гальмування
    local emergencyBrake = false
    local brakeRate = 0
    
    -- SPECIAL: Перший раз перевищили 100% - різко скидаємо швидкість
    -- Це запобігає "overshoot" (розгін → перевантаження → гальмування → цикл)
    if rawLoadRatio > 1.0 and rawLoadRatio <= 1.05 then
        -- Тільки що перевищили 100% - агресивний скид
        controlZone = "THRESHOLD_BRAKE"
        brakeRate = 2.5  -- -2.5 км/год (агресивно, щоб load впав)
        emergencyBrake = true
        newSpeedLimit = math.max(2, self.speedLimit - brakeRate)
        
    elseif rawLoadRatio > 1.5 then
        -- EXTREME: >150% load - максимальне гальмування
        controlZone = "EMERGENCY_EXTREME"
        brakeRate = 5.0  -- -5 км/год за раз
        emergencyBrake = true
        newSpeedLimit = math.max(2, self.speedLimit - brakeRate)
        
    elseif rawLoadRatio > 1.2 then
        -- CRITICAL: 120-150% load - сильне гальмування
        controlZone = "EMERGENCY_CRITICAL"
        brakeRate = 3.0  -- -3 км/год за раз
        emergencyBrake = true
        newSpeedLimit = math.max(2, self.speedLimit - brakeRate)
        
    elseif rawLoadRatio > 1.1 then
        -- HIGH: 110-120% load - помірне гальмування
        controlZone = "EMERGENCY_HIGH"
        brakeRate = 1.5  -- -1.5 км/год за раз
        emergencyBrake = true
        newSpeedLimit = math.max(2, self.speedLimit - brakeRate)
        
    elseif rawLoadRatio > 1.05 or loadRatio > 1.08 then
        -- MODERATE: 105-110% load - легке гальмування
        controlZone = "EMERGENCY_MODERATE"
        brakeRate = 1.0  -- -1 км/год за раз
        emergencyBrake = true
        newSpeedLimit = math.max(2, self.speedLimit - brakeRate)
    
    -- ZONE 1: DANGER (>108% smoothed OR >115% raw) - Standard brake
    elseif loadRatio > 1.08 or rawLoadRatio > 1.15 then
        controlZone = "DANGER"
        if rawLoadRatio > 1.15 then
            -- HARD brake (using raw value for immediate response)
            newSpeedLimit = math.max(2, math.min(self.speedLimit, avgSpeed * 3.6) - 15 * (rawLoadRatio - 1.0)^2)
        else
            -- Soft brake (using smoothed value)
            newSpeedLimit = math.max(2, math.min(self.speedLimit, avgSpeed * 3.6) - 8 * (loadRatio - 1.0)^2)
        end
    
    -- ZONE 2: CAUTION (85-108%) - Hold steady or gentle adjustment
    elseif loadRatio >= 0.85 and loadRatio <= 1.08 then
        controlZone = "CAUTION"
        -- В зоні обережності активно утримуємо швидкість
        if loadRatio > 1.00 then
            -- >100%: Легке гальмування (щоб не доводити до emergency)
            newSpeedLimit = math.max(2, self.speedLimit - 0.4)
        elseif loadRatio > 0.90 and self.speedLimit > avgSpeed * 3.6 then
            -- 90-100%: Якщо швидкість зростає (ззовні), обмежуємо
            newSpeedLimit = math.max(2, avgSpeed * 3.6 - 0.2)
        end
        -- else: <90% в CAUTION - тримаємо стабільно
    
    -- ZONE 3: SAFE (<85%) - Accelerate with prediction
    else
        controlZone = "SAFE"
        
        -- Check prediction before accelerating
        local predictLimitSet = false
        if areaAcc > 0 then
            -- Adaptive prediction horizon (shorter at high load)
            local predictHorizon = 2500 + 500 * (1 - loadRatio)
            local predictAvgArea = self.currentAvgArea + areaAcc * predictHorizon
            
            -- FIXED: Підняли поріг з 1.3 до 1.5
            -- Це запобігає передчасному гальмуванню при 90% load
            local predictThreshold = 1.5
            
            if predictAvgArea > predictThreshold * maxAvgArea then
                -- Predictive brake
                newSpeedLimit = math.max(2, math.min(0.96 * self.speedLimit, avgSpeed * 3.6))
                predictLimitSet = true
                controlZone = "SAFE_PREDICT"
            end
        end
        
        -- If no prediction triggered, check for acceleration
        if not predictLimitSet then
            -- === SOFT CEILING AT 85% ===
            -- Якщо load наближається до 85%, обмежуємо розгін
            -- Але якщо вже на 85% (через зміну густини) - не гальмуємо
            if loadRatio > 0.70 and loadRatio < 0.80 then
                -- 70-80%: Обережний розгін (не хочемо перевищити 85%)
                -- Розганяємось тільки якщо є великий запас
                local capacityRatio = (maxAvgArea - self.currentAvgArea) / maxAvgArea
                if capacityRatio > 0.25 then  -- Тільки якщо запас >25%
                    local accelFactor = 0.05  -- Повільний розгін
                    newSpeedLimit = math.min(self.genuineSpeedLimit, 
                        self.speedLimit + accelFactor * (maxAvgArea / self.currentAvgArea)^2)
                end
                -- else: запас малий - тримаємо поточну швидкість
                
            elseif loadRatio <= 0.70 then
                -- <70%: Нормальний розгін (далеко від стелі)
                local capacityRatio = (maxAvgArea - self.currentAvgArea) / maxAvgArea
                local accelFactor = 0.08 + 0.05 * capacityRatio  -- 0.08-0.13 range
                newSpeedLimit = math.min(self.genuineSpeedLimit, 
                    self.speedLimit + accelFactor * (maxAvgArea / self.currentAvgArea)^2.5)
            end
            -- else: 80%+ в SAFE зоні - тримаємо (не розганяємо, не гальмуємо)
        end
    end
    
    -- === RATE LIMITING === (prevent jerky changes)
    -- Використовуємо різні ліміти залежно від зони
    local maxChange = 0.8  -- Default: 0.8 km/h change per update
    
    if emergencyBrake then
        -- В аварійних ситуаціях дозволяємо швидкі зміни
        maxChange = brakeRate  -- Використовуємо розрахований brakeRate
    elseif controlZone == "DANGER" then
        maxChange = 1.5  -- Швидші зміни в небезпечній зоні
    end
    
    newSpeedLimit = math.clamp(newSpeedLimit, 
        self.speedLimit - maxChange, 
        self.speedLimit + maxChange)
    
    self.speedLimit = newSpeedLimit
    
    if self.debug then
        print(string.format("RHM: [%s] Load: %.1f%% (Raw: %.1f%%) | Speed: %.1f→%.1f | Acc: %.4f", 
            controlZone, loadRatio * 100, rawLoadRatio * 100, 
            avgSpeed * 3.6, self.speedLimit, areaAcc))
    end
end

---Отримує поточне навантаження на двигун
---@return number Навантаження в відсотках (0-100+)
function LoadCalculator:getEngineLoad()
    return self.engineLoad * 100
end

---Отримує поточний ліміт швидкості
---@return number Ліміт швидкості в км/год
function LoadCalculator:getSpeedLimit()
    return self.speedLimit or 0
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
    
    -- Скидаємо накопичення продуктивності
    self.productivityMass = 0
    self.productivityTime = 0
    self.tonPerHour = 0
    
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
    
    -- Накопичуємо масу та час
    self.productivityMass = self.productivityMass + mass
    self.productivityTime = self.productivityTime + dt
    
    -- Оновлюємо T/h кожні 3 секунди для стабільного значення
    if self.productivityTime >= self.productivityUpdateInterval then
        if self.productivityTime > 0 then
            -- Розраховуємо T/h: (кг / мс) * 3600 = т/год
            self.tonPerHour = (self.productivityMass / self.productivityTime) * 3600
        end
        
        -- Скидаємо накопичення з невеликим перекриттям для плавності
        self.productivityMass = self.productivityMass * 0.2
        self.productivityTime = self.productivityTime * 0.2
    end
end





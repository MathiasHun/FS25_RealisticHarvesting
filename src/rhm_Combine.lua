---@class rhm_Combine
rhm_Combine = {}
rhm_Combine.debug = false

---Перевіряє чи машина підходить для цієї спеціалізації
---@param specializations table<string, table>
---@return boolean
function rhm_Combine.prerequisitesPresent(specializations)
    -- DEBUG: Виводимо всі specializations щоб побачити що має Nexat
    print("========================================")
    print("RHM: Checking prerequisites for vehicle")
    print("Available specializations:")
    for specName, specTable in pairs(specializations) do
        if type(specTable) == "table" and specTable.className then
            print("  - " .. specTable.className)
        end
    end
    
    -- Перевіряємо базову specialization Combine
    local hasCombine = SpecializationUtil.hasSpecialization(Combine, specializations)
    print("Has Combine: " .. tostring(hasCombine))
    
    -- Для Nexat: тимчасово спрощуємо перевірку
    -- Повертаємо true якщо просто є Combine
    print("Result: " .. tostring(hasCombine))
    print("========================================")
    
    return hasCombine
end

-- Реєстрація перевизначених функцій (ОБОВ'ЯЗКОВО перед registerEventListeners!)
function rhm_Combine.registerOverwrittenFunctions(vehicleType)
    print("RHM: Registering overwritten functions for rhm_Combine")
    -- SpecializationUtil.registerOverwrittenFunction(vehicleType, "processCutters", rhm_Combine.processCutters) -- Removed: Not needed and was causing nil error
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addCutterArea", rhm_Combine.addCutterArea)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", rhm_Combine.getSpeedLimit)
    -- SpecializationUtil.registerOverwrittenFunction(vehicleType, "setIsTurnedOn", rhm_Combine.setIsTurnedOn)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "startThreshing", rhm_Combine.startThreshing)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "stopThreshing", rhm_Combine.stopThreshing)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "verifyCombine", rhm_Combine.verifyCombine)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", rhm_Combine.getCanBeTurnedOn)
end

function rhm_Combine.registerEventListeners(vehicleType)
    print("RHM: Registering event listeners for rhm_Combine")
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", rhm_Combine)
    
    -- SAVEGAME: Збереження та завантаження стану
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", rhm_Combine)
    
    -- SAVEGAME XML: Disabled - functions are commented out
    -- SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", rhm_Combine)
    -- SpecializationUtil.registerEventListener(vehicleType, "loadFromXMLFile", rhm_Combine)
    
    -- MULTIPLAYER: Синхронізація даних між сервером і клієнтом
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", rhm_Combine)
end

-- Викликається при завантаженні комбайна
function rhm_Combine:onLoad(savegame)
    -- Створюємо spec для нашого моду
    -- Використовуємо пряму назву так як g_currentModName не доступний тут
    local specName = "spec_FS25_RealisticHarvesting.rhm_Combine"
    self.spec_rhm_Combine = self[specName]
    local spec = self.spec_rhm_Combine
    
    if not spec then
        Logging.error("RHM: Failed to initialize spec for combine: %s (specName: %s)", 
            tostring(self:getFullName()), tostring(specName))
        return
    end
    
    if rhm_Combine.debug then
        print(string.format("RHM: onLoad called for %s (has savegame: %s)", 
            tostring(self:getFullName()), tostring(savegame ~= nil)))
    end
    
    -- Створюємо LoadCalculator з modDirectory
    local modDir = g_realisticHarvestManager and g_realisticHarvestManager.modDirectory or g_currentModDirectory
    
    if not LoadCalculator then
        Logging.error("RHM: LoadCalculator class is missing! Check script loading order.")
        return
    end

    spec.loadCalculator = LoadCalculator.new(modDir)
    
    if not spec.loadCalculator then
        Logging.error("RHM: Failed to create LoadCalculator for combine: %s", self:getFullName())
        return
    end
    
    -- Отримуємо базову продуктивність з потужності двигуна
    local basePerf = spec.loadCalculator:getBasePerformanceFromPower(self)
    spec.loadCalculator:setBasePerformance(basePerf)
    
    -- Ініціалізуємо дані для HUD
    spec.data = {
        speed = 0,
        load = 0,
        cropLoss = 0,
        tonPerHour = 0,
        recommendedSpeed = 0  -- Буде оновлено в onUpdateTick на сервері та синхронізовано до клієнтів
    }
    
    -- Лічильник для збереження площі з addCutterArea
    spec.lastArea = 0
    spec.lastLiters = 0  -- Літри зібраного врожаю
    
    -- Відстеження поточної жатки для визначення зміни
    spec.currentCutter = nil
    
    -- Прапорець чи активне обмеження швидкості
    spec.isSpeedLimitActive = false
    
    -- MULTIPLAYER: Dirty flag для синхронізації
    spec.dirtyFlag = self:getNextDirtyFlag()
end

-- Перехоплюємо addCutterArea для отримання площі
-- Hook для addCutterArea щоб перехопити кількість зібраного
-- Argument 2 is actually 'realArea' (actual cut area), not liters!
function rhm_Combine:addCutterArea(superFunc, area, realArea, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    -- Викликаємо оригінальну функцію СПЕРШУ, щоб отримати реальні дані
    local retLiters, retStrawLiters = superFunc(self, area, realArea, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    
    local spec = self.spec_rhm_Combine
    if not spec or not spec.loadCalculator then
        return retLiters, retStrawLiters
    end
    
    -- Отримуємо lastMultiplier (для сумісності зі старою логікою)
    local multiplier = 1.0
    
    -- Зберігаємо РЕАЛЬНУ площу (realArea) якщо вона доступна, інакше area
    local areaForYield = realArea or area
    
    -- Зберігаємо площу для LoadCalculator (стара логіка)
    spec.lastArea = (spec.lastArea or 0) + (area * multiplier)
    
    -- Зберігаємо площу для Yield Monitor
    spec.lastRawArea = (spec.lastRawArea or 0) + areaForYield
    spec.lastMultiplier = multiplier
    
    -- Зберігаємо ЛІТРИ (результат жнив)
    if retLiters and retLiters > 0 then
        spec.lastLiters = (spec.lastLiters or 0) + retLiters
    end
    
    -- Зберігаємо тип культури
    if outputFillType and outputFillType ~= FillType.UNKNOWN then
        spec.lastFillType = outputFillType
    end
    
    -- DEBUG: Uncomment to see values in console
    -- if (retLiters or 0) > 0 then
    --     print(string.format("RHM: cut=%.4f real=%.4f L=%.4f", area, realArea, retLiters))
    -- end
    
    return retLiters, retStrawLiters
end

-- Перевизначаємо getSpeedLimit для автоматичного обмеження швидкості
function rhm_Combine:getSpeedLimit(superFunc, onlyIfWorking)
    local spec = self.spec_rhm_Combine
    
    -- Викликаємо оригінальну функцію
    local limit, doCheckSpeedLimit = superFunc(self, onlyIfWorking)
    
    -- Якщо spec не ініціалізований, повертаємо оригінальний ліміт
    if not spec or not spec.loadCalculator then
        return limit, doCheckSpeedLimit
    end
    
    -- Перевіряємо чи комбайн працює
    if not self:getIsTurnedOn() then
        spec.isSpeedLimitActive = false
        return limit, doCheckSpeedLimit
    end
    
    -- CRITICAL FIX: Перевіряємо чи жатка ПРАЦЮЄ (не просто прикріплена)
    -- Якщо жатка піднята або не косить - НЕ обмежуємо швидкість
    local spec_combine = self.spec_combine
    local cutterIsWorking = false
    
    if spec_combine and spec_combine.attachedCutters then
        for cutter, _ in pairs(spec_combine.attachedCutters) do
            if cutter.spec_cutter then
                local spec_cutter = cutter.spec_cutter
                -- Жатка працює якщо: рух вперед, швидкість > 0.5, опущена (або дозволено косити піднятою)
                cutterIsWorking = self.movingDirection == spec_cutter.movingDirection 
                    and self:getLastSpeed() > 0.5 
                    and (spec_cutter.allowCuttingWhileRaised or cutter:getIsLowered(true))
                
                if cutterIsWorking then
                    break -- Знайшли працюючу жатку
                end
            end
        end
    end
    
    -- Якщо жатка НЕ працює - знімаємо обмеження відразу
    if not cutterIsWorking then
        spec.isSpeedLimitActive = false
        return limit, doCheckSpeedLimit
    end
    
    -- Перевіряємо чи увімкнено обмеження швидкості
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        if not g_realisticHarvestManager.settings.enableSpeedLimit then
            spec.isSpeedLimitActive = false
            return limit, doCheckSpeedLimit
        end
        
        -- В Arcade режимі НЕ обмежуємо швидкість (як у ванільній грі)
        if g_realisticHarvestManager.settings.difficulty == 1 then -- DIFFICULTY_ARCADE
            spec.isSpeedLimitActive = false
            return limit, doCheckSpeedLimit
        end
    end
    
    -- Перевіряємо чи змінилася жатка
    if spec_combine and spec_combine.attachedCutters then
        local currentCutter = nil
        for cutter, _ in pairs(spec_combine.attachedCutters) do
            currentCutter = cutter
            break -- Беремо першу жатку
        end
        
        -- Якщо жатка змінилася, скидаємо genuineSpeedLimit
        if currentCutter ~= spec.currentCutter and currentCutter ~= nil then
            spec.currentCutter = currentCutter
            spec.loadCalculator.genuineSpeedLimit = 15 -- Скидаємо до початкового значення
            -- Logging.info("RHM: [getSpeedLimit] Cutter changed, resetting genuineSpeedLimit")
        end
    end
    
    -- Встановлюємо оригінальний ліміт в LoadCalculator ТІЛЬКИ ОДИН РАЗ
    -- Перевіряємо чи genuineSpeedLimit ще не ініціалізований (дорівнює початковому значенню 15)
    -- І перевіряємо що limit - це реальне число (не inf)
    if spec.loadCalculator.genuineSpeedLimit == 15 and limit ~= math.huge then
        -- Використовуємо 1.5x від ліміту гри, мінімум 18 км/год
        -- Це дозволяє комбайну їхати швидше на легких полях!
        local genuineLimit = math.max(1.5 * limit, 18.0)
        spec.loadCalculator:setGenuineSpeedLimit(genuineLimit)
        -- Logging.info("RHM: [getSpeedLimit] Initial genuine limit set to %.1f km/h (from game limit %.1f)", 
        --     genuineLimit, limit)
    end
    
    -- === MULTIPLAYER FIX ===
    -- На клієнті LoadCalculator НЕ оновлюється (тільки на сервері)
    -- Тому клієнт повинен використовувати синхронізоване значення spec.data.recommendedSpeed
    if not self.isServer then
        -- CLIENT: Use synced value from server
        if spec.data and spec.data.recommendedSpeed then
            local syncedLimit = spec.data.recommendedSpeed
            
            -- Apply synced limit if it's actively limiting (< genuineSpeedLimit)
            if syncedLimit < spec.loadCalculator.genuineSpeedLimit then
                spec.isSpeedLimitActive = true
                limit = syncedLimit
            else
                spec.isSpeedLimitActive = false
            end
        end
        
        return limit, doCheckSpeedLimit
    end
    
    -- === SERVER: Continue with normal LoadCalculator logic ===
    -- Отримуємо обмеження з LoadCalculator
    local calculatedLimit = spec.loadCalculator:getSpeedLimit()
    local engineLoad = spec.loadCalculator:getEngineLoad()
    
    -- Діагностика: логуємо розрахунки (рідше)
    if not self._speedLimitLogTime or (g_currentMission.time - self._speedLimitLogTime) > 2000 then
        -- Logging.info("RHM: [getSpeedLimit] Load: %.1f%%, Calc limit: %.1f, Orig limit: %.1f", 
        --     engineLoad, calculatedLimit, limit)
        self._speedLimitLogTime = g_currentMission.time
    end
    
    -- ЗАВЖДИ застосовуємо розрахований ліміт (не порівнюємо з оригінальним)
    -- Це дозволяє обмежувати швидкість навіть якщо вона менша за оригінальний ліміт гри
    if calculatedLimit < spec.loadCalculator.genuineSpeedLimit then
        spec.isSpeedLimitActive = true
        limit = calculatedLimit
        
        -- Логуємо тільки коли РЕАЛЬНО обмежуємо
        if not self._lastLimitLog or math.abs(self._lastLimitLog - limit) > 0.5 then
            -- Logging.info("RHM: [getSpeedLimit] *** LIMITING SPEED to %.1f km/h (load: %.1f%%) ***", 
            --     limit, engineLoad)
            self._lastLimitLog = limit
        end
    else
        spec.isSpeedLimitActive = false
    end
    
    return limit, doCheckSpeedLimit
end

-- Перевіряємо чи можна увімкнути комбайн
function rhm_Combine:getCanBeTurnedOn(superFunc)
    local spec_combine = self.spec_combine
    
    -- Якщо немає жаток, використовуємо стандартну логіку
    if spec_combine.numAttachedCutters <= 0 then
        return superFunc(self)
    end
    
    -- Перевіряємо кожну жатку
    for cutter, _ in pairs(spec_combine.attachedCutters) do
        if cutter ~= self and cutter.getCanBeTurnedOn ~= nil and not cutter:getCanBeTurnedOn() then
            -- Якщо хоч одна жатка не готова (наприклад складена), комбайн не запуститься
            return false
        end
    end

    return superFunc(self)
end

-- Запобігаємо автозапуску жатки при старті молотарки
-- ВАЖЛИВО: НЕ викликаємо superFunc, бо він запускає жатки автоматично!
function rhm_Combine:startThreshing(superFunc)
    local spec_combine = self.spec_combine
    
    -- Перевіряємо чи увімкнена функція роздільного запуску
    local isIndependentLaunchEnabled = false
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        isIndependentLaunchEnabled = g_realisticHarvestManager.settings.enableIndependentLaunch
    end
    
    -- Логіка запуску жаток:
    -- - Якщо роздільний запуск ВИМКНЕНИЙ → запускаємо жатки завжди (класична поведінка)
    -- - Якщо роздільний запуск УВІМКНЕНИЙ → запускаємо ТІЛЬКИ для AI
    local isAIActive = self:getIsAIActive()
    local shouldStartCutters = (not isIndependentLaunchEnabled) or (isIndependentLaunchEnabled and isAIActive)
    
    if spec_combine.numAttachedCutters > 0 and shouldStartCutters then
        -- Запускаємо жатки (для AI завжди, для гравця - тільки якщо функція вимкнена)
        local allowLowering = not self:getIsAIActive() or not self.rootVehicle:getAIFieldWorkerIsTurning()
        
        for _, cutter in pairs(spec_combine.attachedCutters) do
            if allowLowering and cutter ~= self then
                local jointDescIndex = self:getAttacherJointIndexFromObject(cutter)
                self:setJointMoveDown(jointDescIndex, true, true)
            end
            
            cutter:setIsTurnedOn(true, true)
        end
    end
    
    -- Анімації та звуки молотарки (завжди)
    if spec_combine.threshingStartAnimation ~= nil and self.playAnimation ~= nil then
        self:playAnimation(spec_combine.threshingStartAnimation, spec_combine.threshingStartAnimationSpeedScale, self:getAnimationTime(spec_combine.threshingStartAnimation), true)
    end
    
    if self.isClient then
        g_soundManager:stopSample(spec_combine.samples.stop)
        g_soundManager:stopSample(spec_combine.samples.work)
        g_soundManager:playSample(spec_combine.samples.start)
        g_soundManager:playSample(spec_combine.samples.work, 0, spec_combine.samples.start)
    end
    
    SpecializationUtil.raiseEvent(self, "onStartThreshing")
end

-- Запобігаємо авто-вимкненню жатки при зупинці молотарки
function rhm_Combine:stopThreshing(superFunc)
    local spec_combine = self.spec_combine
    
    if self.isClient then
        g_soundManager:stopSample(spec_combine.samples.start)
        g_soundManager:stopSample(spec_combine.samples.work)
        g_soundManager:playSample(spec_combine.samples.stop)
    end
    
    self:setCombineIsFilling(false, false, true)
    local isFull = self:getCombineFillLevelPercentage() > 0.999
    if isFull and self.rootVehicle.setCruiseControlState ~= nil then
        self.rootVehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
    end
    
    -- НЕ вимикаємо жатки автоматично (гравець керує ними вручну)
    
    if spec_combine.threshingStartAnimation ~= nil and spec_combine.playAnimation ~= nil then
        self:playAnimation(spec_combine.threshingStartAnimation, -spec_combine.threshingStartAnimationSpeedScale, self:getAnimationTime(spec_combine.threshingStartAnimation), true)
    end
    
    SpecializationUtil.raiseEvent(self, "onStopThreshing")
end

-- Забороняємо харвестинг якщо комбайн вимкнений
-- Це запобігає збору врожаю коли увімкнена тільки жатка без комбайна
function rhm_Combine:verifyCombine(superFunc, fruitType, outputFillType)
    local isAIActive = self:getIsAIActive()
    
    -- Перевіряємо чи комбайн увімкнений (молотарка працює)
    if not self:getIsTurnedOn() and not isAIActive then
        return nil  -- Блокуємо харвестинг
    end
    
    return superFunc(self, fruitType, outputFillType)
end

-- Викликається періодично для оновлення логіки
function rhm_Combine:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if rhm_Combine.debug then
        print("RHM: rhm_Combine:onUpdateTick called")
    end
    
    if not self.isServer then
        return
    end
    
    local spec = self.spec_rhm_Combine
    local spec_combine = self.spec_combine
    
    if not spec or not spec.loadCalculator then
        return
    end
    
    -- Перевіряємо чи комбайн працює
    if not self:getIsTurnedOn() or self.movingDirection == -1 then
        -- Комбайн не працює - скидаємо навантаження
        spec.loadCalculator:reset()
        if spec.data then
            spec.data.load = 0
        end
        spec.isSpeedLimitActive = false
        return
    end
    
    -- Перевіряємо чи жатка працює
    local cutterIsTurnedOn = false
    for cutter, _ in pairs(spec_combine.attachedCutters) do
        if cutter.spec_cutter then
            local spec_cutter = cutter.spec_cutter
            cutterIsTurnedOn = self.movingDirection == spec_cutter.movingDirection 
                and self:getLastSpeed() > 0.5 
                and (spec_cutter.allowCuttingWhileRaised or cutter:getIsLowered(true))
        end
    end
    
    if not cutterIsTurnedOn then
        -- Жатка не працює (але не скидаємо loadCalculator повністю, щоб уникнути стрибків при зупинках)
        -- spec.loadCalculator:reset() -- ВИДАЛЕНО: Викликало нестабільність при короткочасних зупинках
        if spec.data then
            -- spec.data.load = 0 -- Не обнуляємо візуально, хай показує останнє
        end
        spec.isSpeedLimitActive = false
        return
    end
    
    -- Оновлюємо LoadCalculator
    -- Спершу розраховуємо масу, бо тепер вона головна!
    local massKg = 0
    local liters = spec.lastLiters or 0
    
    if liters > 0 then
        if spec.lastFillType and g_fillTypeManager then
            local fillType = g_fillTypeManager:getFillTypeByIndex(spec.lastFillType)
            if fillType and fillType.massPerLiter then
                -- ВАЖЛИВО: massPerLiter в грі зберігається в ТОННАХ на літр, тому множимо на 1000
                massKg = liters * fillType.massPerLiter * 1000
            else
                massKg = liters * 0.75 -- Fallback
            end
        else
            massKg = liters * 0.75 -- Fallback
        end
    end
    
    -- Використовуємо lastRawArea (реальна площа) для врожайності
    local areaForYield = spec.lastRawArea or spec.lastArea or 0 
    
    -- Передаємо МАСУ в LoadCalculator!
    spec.loadCalculator:update(self, dt, massKg)
    
    -- Оновлюємо продуктивність і врожайність
    if liters > 0 then
        -- Використовуємо нову функцію з area
        spec.loadCalculator:updateProductivityAndYield(massKg, liters, areaForYield, dt) 
    end
    
    -- Скидаємо лічильники
    spec.lastArea = 0
    spec.lastRawArea = 0 -- Reset new counter
    spec.lastLiters = 0
    
    -- Оновлюємо дані для HUD
    if spec.data then
        spec.data.load = spec.loadCalculator:getEngineLoad()
        spec.data.cropLoss = spec.loadCalculator:calculateCropLoss()
        spec.data.tonPerHour = spec.loadCalculator:getTonPerHour()
        spec.data.litersPerHour = spec.loadCalculator:getLitersPerHour() -- NEW: Volume flow
        spec.data.recommendedSpeed = spec.loadCalculator:getSpeedLimit()
        -- NEW: Yield Monitor Data
        spec.data.yield = spec.loadCalculator.currentYield or 0
    end
    
    -- MULTIPLAYER: Позначаємо що дані змінились для синхронізації
    self:raiseDirtyFlags(spec.dirtyFlag)
    
    if rhm_Combine.debug then
        print(string.format("RHM: Engine load updated: %.1f%%, Speed limit: %.1f km/h", 
            spec.data.load, spec.loadCalculator:getSpeedLimit()))
    end
end

-- Викликається кожен кадр коли гравець в комбайні
-- Викликається кожен кадр коли гравець в комбайні
function rhm_Combine:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    -- ПРИМІТКА: HUD малюється централізовано в RealisticHarvestManager:draw()
    -- Ми використовуємо сканування ієрархії (getControlledVehicle -> root -> findCombine),
    -- тому немає потреби малювати тут, це викликає дублювання.
end

-- ============================================================================
-- SAVEGAME FUNCTIONS  
-- ============================================================================

---Збереження стану в savegame файл
---@param xmlFile XMLFile
---@param key string
-- saveToXMLFile disabled - causes XML schema validation errors
-- Values are calculated dynamically, no need to save/load
--[[function rhm_Combine:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_rhm_Combine
    if not spec then
        return
    end
    
    -- Зберігаємо базову продуктивність LoadCalculator
    if spec.loadCalculator then
        xmlFile:setValue(key .. "#basePerformance", spec.loadCalculator.basePerformance or 0)
        xmlFile:setValue(key .. "#genuineSpeedLimit", spec.loadCalculator.genuineSpeedLimit or 15)
    end
    
    if rhm_Combine.debug then
        print("RHM: saveToXMLFile completed for " .. tostring(self:getFullName()))
    end
end--]]

-- loadFromXMLFile disabled - causes XML schema validation errors
-- Values are calculated dynamically, no need to save/load
--[[---Завантаження стану з savegame файлу
---@param xmlFile XMLFile
---@param key string  
---@param resetVehicles table
function rhm_Combine:loadFromXMLFile(xmlFile, key, resetVehicles)
    if rhm_Combine.debug then
        print(string.format("RHM: loadFromXMLFile called for %s with key: %s", 
            tostring(self:getFullName()), tostring(key)))
    end
    
    local spec = self.spec_rhm_Combine
    if not spec then
        if rhm_Combine.debug then
            print("RHM: loadFromXMLFile - spec not found, skipping")
        end
        return
    end
    
    if not spec.loadCalculator then
        if rhm_Combine.debug then
            print("RHM: loadFromXMLFile - loadCalculator not found, skipping")
        end
        return
    end
    
    -- Безпечне завантаження базової продуктивності з default значенням
    local basePerf = xmlFile:getValue(key .. "#basePerformance", spec.loadCalculator.basePerfMass)
    if basePerf and tonumber(basePerf) and basePerf > 0 then
        spec.loadCalculator:setBasePerformance(tonumber(basePerf))
        if rhm_Combine.debug then
            print(string.format("RHM: Loaded basePerformance: %.2f kg/s", basePerf))
        end
    end
    
    -- Безпечне завантаження genuineSpeedLimit з default значенням  
    local speedLimit = xmlFile:getValue(key .. "#genuineSpeedLimit", spec.loadCalculator.genuineSpeedLimit)
    if speedLimit and tonumber(speedLimit) and speedLimit > 0 then
        spec.loadCalculator:setGenuineSpeedLimit(tonumber(speedLimit))
        if rhm_Combine.debug then
            print(string.format("RHM: Loaded genuineSpeedLimit: %.1f km/h", speedLimit))
        end
    end
    
    if rhm_Combine.debug then
        print(string.format("RHM: loadFromXMLFile completed for %s", tostring(self:getFullName())))
    end
end--]]

-- ============================================================================
-- MULTIPLAYER SYNCHRONIZATION
-- ============================================================================

---Початкова синхронізація: Сервер пише дані коли клієнт підключається
function rhm_Combine:onWriteStream(streamId, connection)
    local spec = self.spec_rhm_Combine
    if not spec or not spec.data then
        -- Пишемо нулі якщо немає даних
        streamWriteFloat32(streamId, 0)
        streamWriteFloat32(streamId, 0)
        streamWriteFloat32(streamId, 0)
        streamWriteFloat32(streamId, 0)
        streamWriteFloat32(streamId, 0) -- litersPerHour
        streamWriteFloat32(streamId, 0) -- yield
        return
    end
    
    streamWriteFloat32(streamId, spec.data.load or 0)
    streamWriteFloat32(streamId, spec.data.cropLoss or 0)
    streamWriteFloat32(streamId, spec.data.tonPerHour or 0)
    streamWriteFloat32(streamId, spec.data.litersPerHour or 0) -- litersPerHour
    streamWriteFloat32(streamId, spec.data.recommendedSpeed or 0)
    streamWriteFloat32(streamId, spec.data.yield or 0)
end

---Початкова синхронізація: Клієнт читає дані при підключенні
function rhm_Combine:onReadStream(streamId, connection)
    local spec = self.spec_rhm_Combine
    if not spec then
        -- Пропускаємо дані якщо немає spec
        streamReadFloat32(streamId)
        streamReadFloat32(streamId)
        streamReadFloat32(streamId)
        streamReadFloat32(streamId)
        streamReadFloat32(streamId)
        streamReadFloat32(streamId) -- yield
        return
    end
    
    if not spec.data then
        spec.data = {}
    end
    
    spec.data.load = streamReadFloat32(streamId)
    spec.data.cropLoss = streamReadFloat32(streamId)
    spec.data.tonPerHour = streamReadFloat32(streamId)
    spec.data.litersPerHour = streamReadFloat32(streamId)
    spec.data.recommendedSpeed = streamReadFloat32(streamId)
    spec.data.yield = streamReadFloat32(streamId)
end

---Постійна синхронізація: Клієнт читає оновлення від сервера
function rhm_Combine:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then  -- Клієнт читає від сервера
        local spec = self.spec_rhm_Combine
        if not spec then 
            return 
        end
        
        -- Перевіряємо чи є оновлення (dirtyFlag)
        local hasUpdate = streamReadBool(streamId)
        
        if hasUpdate then
            if not spec.data then
                spec.data = {}
            end
            
            spec.data.load = streamReadFloat32(streamId)
            spec.data.cropLoss = streamReadFloat32(streamId)
            spec.data.tonPerHour = streamReadFloat32(streamId)
            spec.data.litersPerHour = streamReadFloat32(streamId)
            spec.data.recommendedSpeed = streamReadFloat32(streamId)
            spec.data.yield = streamReadFloat32(streamId)

        end
    end
end

---Постійна синхронізація: Сервер пише оновлення до клієнта
function rhm_Combine:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then  -- Сервер пише до клієнта
        local spec = self.spec_rhm_Combine
        if not spec then
            streamWriteBool(streamId, false)
            return
        end
        
        -- Перевіряємо чи є зміни
        local hasChanges = bitAND(dirtyMask, spec.dirtyFlag) ~= 0
        
        streamWriteBool(streamId, hasChanges)
        
        if hasChanges then
            if not spec.data then
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0) -- yield
                return
            end

            
            streamWriteFloat32(streamId, spec.data.load or 0)
            streamWriteFloat32(streamId, spec.data.cropLoss or 0)
            streamWriteFloat32(streamId, spec.data.tonPerHour or 0)
            streamWriteFloat32(streamId, spec.data.litersPerHour or 0)
            streamWriteFloat32(streamId, spec.data.recommendedSpeed or 0)
            streamWriteFloat32(streamId, spec.data.yield or 0)
        end
    end
end





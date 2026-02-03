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
end

function rhm_Combine.registerEventListeners(vehicleType)
    print("RHM: Registering event listeners for rhm_Combine")
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", rhm_Combine)
    
    -- SAVEGAME: Збереження та завантаження стану
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", rhm_Combine)
    
    -- SAVEGAME XML: Критично важливо для збереження гри!
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "loadFromXMLFile", rhm_Combine)
    
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
function rhm_Combine:addCutterArea(superFunc, area, liters, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    local spec = self.spec_rhm_Combine
    
    if not spec then
        return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    end
    
    -- Отримуємо lastMultiplier з workAreaParameters жатки
    -- Цей множник враховує добрива (0-100%), густину врожаю, вологість
    local multiplier = 1.0
    local spec_combine = self.spec_combine
    if spec_combine and spec_combine.attachedCutters then
        for cutter, _ in pairs(spec_combine.attachedCutters) do
            if cutter.spec_cutter and cutter.spec_cutter.workAreaParameters then
                local params = cutter.spec_cutter.workAreaParameters
                if params.lastArea and params.lastArea > 0 and params.lastMultiplierArea then
                    multiplier = params.lastMultiplierArea / params.lastArea
                    -- Логування для діагностики
                    if rhm_Combine.debug and multiplier ~= 1.0 then
                        print(string.format("RHM: lastMultiplier = %.2f (fertilizer/density factor)", multiplier))
                    end
                end
            end
        end
    end
    
    if rhm_Combine.debug then
        print(string.format("RHM: addCutterArea called. Liters: %.2f, Area: %.2f, Mult: %.2f", liters or 0, area or 0, multiplier))
    end
    
    -- Зберігаємо площу для LoadCalculator з урахуванням множника!
    spec.lastArea = (spec.lastArea or 0) + (area * multiplier)
    spec.lastMultiplier = multiplier
    
    -- Зберігаємо літри для розрахунку продуктивності в onUpdateTick
    spec.lastLiters = (spec.lastLiters or 0) + (liters or 0)
    
    -- Зберігаємо тип культури для визначення маси
    if outputFillType and outputFillType ~= FillType.UNKNOWN then
        spec.lastFillType = outputFillType
    end
    
    -- Викликаємо оригінальну функцію
    return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
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
    local spec_combine = self.spec_combine
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
    
    -- Використовуємо lastArea з spec_combine (встановлюється в addCutterArea)
    -- local area = spec.lastArea or 0 -- Більше не використовується для основного розрахунку
    
    -- Передаємо МАСУ в LoadCalculator!
    spec.loadCalculator:update(self, dt, massKg)
    
    -- Оновлюємо продуктивність (логіку продуктивності теж залишаємо, вона використовує ті самі дані)
    if liters > 0 then
        spec.loadCalculator:updateProductivity(massKg, liters, dt) 
    end
    
    -- Скидаємо лічильники
    spec.lastArea = 0
    spec.lastLiters = 0
    
    -- Оновлюємо дані для HUD
    if spec.data then
        spec.data.load = spec.loadCalculator:getEngineLoad()
        spec.data.cropLoss = spec.loadCalculator:calculateCropLoss()
        spec.data.tonPerHour = spec.loadCalculator:getTonPerHour()
        spec.data.litersPerHour = spec.loadCalculator:getLitersPerHour() -- NEW: Volume flow
        spec.data.recommendedSpeed = spec.loadCalculator:getSpeedLimit()
    end
    
    -- MULTIPLAYER: Позначаємо що дані змінились для синхронізації
    self:raiseDirtyFlags(spec.dirtyFlag)
    
    if rhm_Combine.debug then
        print(string.format("RHM: Engine load updated: %.1f%%, Speed limit: %.1f km/h", 
            spec.data.load, spec.loadCalculator:getSpeedLimit()))
    end
end

-- Викликається кожен кадр коли гравець в комбайні
function rhm_Combine:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_rhm_Combine
    
    -- Перевіряємо чи комбайн запущений
    if not self:getIsTurnedOn() then
        return
    end
    
    -- Отримуємо HUD з глобального менеджера
    if not g_realisticHarvestManager or not g_realisticHarvestManager.hud then
        return
    end
    
    local hud = g_realisticHarvestManager.hud
    
    -- Перевіряємо налаштування showHUD
    if not hud.settings or not hud.settings.showHUD then
        return
    end
    
    -- Встановлюємо активний комбайн для HUD
    hud:setVehicle(self)
    
    -- Малюємо HUD
    hud:draw()
end

-- ============================================================================
-- SAVEGAME FUNCTIONS  
-- ============================================================================

---Збереження стану в savegame файл
---@param xmlFile XMLFile
---@param key string
function rhm_Combine:saveToXMLFile(xmlFile, key, usedModNames)
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
end

---Завантаження стану з savegame файлу
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
end

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
        return
    end
    
    streamWriteFloat32(streamId, spec.data.load or 0)
    streamWriteFloat32(streamId, spec.data.cropLoss or 0)
    streamWriteFloat32(streamId, spec.data.tonPerHour or 0)
    streamWriteFloat32(streamId, spec.data.litersPerHour or 0) -- litersPerHour
    streamWriteFloat32(streamId, spec.data.recommendedSpeed or 0)
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
        
        if streamWriteBool(streamId, hasChanges) then
            if not spec.data then
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                streamWriteFloat32(streamId, 0)
                return
            end

            
            streamWriteFloat32(streamId, spec.data.load or 0)
            streamWriteFloat32(streamId, spec.data.cropLoss or 0)
            streamWriteFloat32(streamId, spec.data.tonPerHour or 0)
            streamWriteFloat32(streamId, spec.data.litersPerHour or 0)
            streamWriteFloat32(streamId, spec.data.recommendedSpeed or 0)
        end
    end
end





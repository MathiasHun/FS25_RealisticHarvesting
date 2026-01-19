---@class rhm_Combine
rhm_Combine = {}

rhm_Combine.debug = false

function rhm_Combine.prerequisitesPresent(specializations)
    -- Наш specialization додається тільки до комбайнів
    return SpecializationUtil.hasSpecialization(Combine, specializations)
end

-- Реєстрація перевизначених функцій (ОБОВ'ЯЗКОВО перед registerEventListeners!)
function rhm_Combine.registerOverwrittenFunctions(vehicleType)
    print("RHM: Registering overwritten functions for rhm_Combine")
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addCutterArea", rhm_Combine.addCutterArea)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", rhm_Combine.getSpeedLimit)
end

function rhm_Combine.registerEventListeners(vehicleType)
    print("RHM: Registering event listeners for rhm_Combine")
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", rhm_Combine)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", rhm_Combine)
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
    
    -- Створюємо LoadCalculator з modDirectory
    spec.loadCalculator = LoadCalculator.new(g_currentModDirectory)
    
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
        tonPerHour = 0
    }
    
    -- Лічильник для збереження площі з addCutterArea
    spec.lastArea = 0
    
    -- Відстеження поточної жатки для визначення зміни
    spec.currentCutter = nil
    
    -- Прапорець чи активне обмеження швидкості
    spec.isSpeedLimitActive = false
end

-- Перехоплюємо addCutterArea для отримання площі
function rhm_Combine:addCutterArea(superFunc, area, liters, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    local spec = self.spec_rhm_Combine
    
    if not spec then
        return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, strawGroundType, farmId, cutterLoad)
    end
    
    -- КРИТИЧНЕ ВИПРАВЛЕННЯ з CombineXP:
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
    
    -- Зберігаємо площу для LoadCalculator з урахуванням множника!
    spec.lastArea = (spec.lastArea or 0) + (area * multiplier)
    spec.lastMultiplier = multiplier
    
    -- Розраховуємо продуктивність (T/h) на основі зібраних літрів
    -- liters → kg (density ~0.75 kg/L для зерна) → tons
    if liters and liters > 0 then
        local massKg = liters * 0.75 -- Приблизна щільність зерна
        -- Оновлюємо продуктивність в LoadCalculator
        if spec.loadCalculator then
            spec.loadCalculator:updateProductivity(massKg, 16.67) -- ~60 FPS = 16.67ms per frame
        end
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
            Logging.info("RHM: [getSpeedLimit] Cutter changed, resetting genuineSpeedLimit")
        end
    end
    
    -- Встановлюємо оригінальний ліміт в LoadCalculator ТІЛЬКИ ОДИН РАЗ
    -- Перевіряємо чи genuineSpeedLimit ще не ініціалізований (дорівнює початковому значенню 15)
    -- І перевіряємо що limit - це реальне число (не inf)
    if spec.loadCalculator.genuineSpeedLimit == 15 and limit ~= math.huge then
        -- КРИТИЧНЕ ВИПРАВЛЕННЯ з CombineXP:
        -- Використовуємо 1.5x від ліміту гри, мінімум 18 км/год
        -- Це дозволяє комбайну їхати швидше на легких полях!
        local genuineLimit = math.max(1.5 * limit, 18.0)
        spec.loadCalculator:setGenuineSpeedLimit(genuineLimit)
        Logging.info("RHM: [getSpeedLimit] Initial genuine limit set to %.1f km/h (from game limit %.1f)", 
            genuineLimit, limit)
    end
    
    -- Отримуємо обмеження з LoadCalculator
    local calculatedLimit = spec.loadCalculator:getSpeedLimit()
    local engineLoad = spec.loadCalculator:getEngineLoad()
    
    -- Діагностика: логуємо розрахунки (рідше)
    if not self._speedLimitLogTime or (g_currentMission.time - self._speedLimitLogTime) > 2000 then
        Logging.info("RHM: [getSpeedLimit] Load: %.1f%%, Calc limit: %.1f, Orig limit: %.1f", 
            engineLoad, calculatedLimit, limit)
        self._speedLimitLogTime = g_currentMission.time
    end
    
    -- ЗАВЖДИ застосовуємо розрахований ліміт (не порівнюємо з оригінальним)
    -- Це дозволяє обмежувати швидкість навіть якщо вона менша за оригінальний ліміт гри
    if calculatedLimit < spec.loadCalculator.genuineSpeedLimit then
        spec.isSpeedLimitActive = true
        limit = calculatedLimit
        
        -- Логуємо тільки коли РЕАЛЬНО обмежуємо
        if not self._lastLimitLog or math.abs(self._lastLimitLog - limit) > 0.5 then
            Logging.info("RHM: [getSpeedLimit] *** LIMITING SPEED to %.1f km/h (load: %.1f%%) ***", 
                limit, engineLoad)
            self._lastLimitLog = limit
        end
    else
        spec.isSpeedLimitActive = false
    end
    
    return limit, doCheckSpeedLimit
end

-- Викликається періодично для оновлення логіки (як у CombineXP)
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
    
    -- Перевіряємо чи жатка працює (як у CombineXP)
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
        -- Жатка не працює - скидаємо навантаження
        spec.loadCalculator:reset()
        if spec.data then
            spec.data.load = 0
        end
        spec.isSpeedLimitActive = false
        return
    end
    
    -- Оновлюємо LoadCalculator
    -- Використовуємо lastArea з spec_combine (встановлюється в addCutterArea)
    local area = spec.lastArea or 0
    spec.loadCalculator:update(self, dt, area)
    
    -- Скидаємо лічильник площі
    spec.lastArea = 0
    
    -- Оновлюємо дані для HUD
    if spec.data then
        spec.data.load = spec.loadCalculator:getEngineLoad()
        spec.data.cropLoss = spec.loadCalculator:calculateCropLoss()
        spec.data.tonPerHour = spec.loadCalculator:getTonPerHour()
    end
    
    if rhm_Combine.debug then
        print(string.format("RHM: Engine load updated: %.1f%%, Speed limit: %.1f km/h", 
            spec.data.load, spec.loadCalculator:getSpeedLimit()))
    end
end

-- Викликається кожен кадр коли гравець в комбайні
function rhm_Combine:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if rhm_Combine.debug then
        print("RHM: rhm_Combine:onDraw called")
    end
    
    local spec = self.spec_rhm_Combine
    
    -- Перевіряємо чи комбайн запущений
    if not self:getIsTurnedOn() then
        if rhm_Combine.debug then
            print("RHM: Combine is not turned on, skipping HUD")
        end
        return
    end
    
    -- Отримуємо HUD з глобального менеджера
    if not g_realisticHarvestManager or not g_realisticHarvestManager.hud then
        if rhm_Combine.debug then
            print("RHM: HUD not available")
        end
        return
    end
    
    local hud = g_realisticHarvestManager.hud
    
    -- Перевіряємо налаштування showHUD
    if not hud.settings or not hud.settings.showHUD then
        if rhm_Combine.debug then
            print("RHM: showHUD is false")
        end
        return
    end
    
    -- Встановлюємо активний комбайн для HUD
    hud:setVehicle(self)
    
    -- Малюємо HUD
    hud:draw()
    
    if rhm_Combine.debug and spec.data then
        print(string.format("RHM: HUD drawn - Speed: %.1f km/h, Load: %.0f%%", spec.data.speed or 0, spec.data.load or 0))
    end
end

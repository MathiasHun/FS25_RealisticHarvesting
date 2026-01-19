---@class HUD
HUD = {}
local HUD_mt = Class(HUD)

function HUD.new(settings, speedMeter, modDirectory)
    local self = setmetatable({}, HUD_mt)
    
    if not settings then
        Logging.error("RHM: Settings is nil - cannot create HUD!")
        return nil
    end
    
    self.settings = settings
    self.speedMeter = speedMeter
    self.modDirectory = modDirectory
    self.vehicle = nil  -- Активний комбайн
    
    -- Лічильники для діагностики
    self.updateCount = 0
    self.drawCount = 0
    self.lastLogTime = 0
    
    -- Дані для відображення (поки що заглушки)
    self.data = {
        title = "Realistic Harvest",
        status = "HUD Active",
        speed = 0,
        load = 0
    }
    
    -- Overlay буде створений в load()
    self.backgroundOverlay = nil
    
    return self
end

-- Встановлює активний комбайн
function HUD:setVehicle(vehicle)
    self.vehicle = vehicle
    
    if vehicle then
        -- Оновлюємо дані з комбайна
        local spec = vehicle.spec_rhm_Combine
        if spec and spec.data then
            self.data.speed = spec.data.speed
            self.data.load = spec.data.load
            self.data.cropLoss = spec.data.cropLoss
            self.data.tonPerHour = spec.data.tonPerHour
        end
        
        -- Отримуємо рекомендовану швидкість з LoadCalculator
        if spec and spec.loadCalculator then
            self.data.recommendedSpeed = spec.loadCalculator:getSpeedLimit()
        end
    end
end

-- Викликається після завантаження місії (як у CombineXP)
function HUD:load()
    if not g_currentMission or not g_currentMission.hud or not g_currentMission.hud.speedMeter then
        Logging.warning("RHM: SpeedMeter not available - cannot create HUD overlay!")
        return
    end
    
    -- Створюємо overlay ТУТ, коли speedMeter вже готовий
    self:createOverlay()
end

function HUD:createOverlay()
    local speedMeter = g_currentMission.hud.speedMeter
    
    -- Компактні розміри для вертикального HUD (4 рядки: LOAD + T/h + LOSS + Speed)
    local boxWidth = 140  -- вужчий
    local boxHeight = 80  -- вище для 4 рядків
    
    -- Конвертуємо в екранні координати
    local width, height = speedMeter:scalePixelToScreenVector({boxWidth, boxHeight})
    
    -- Позиція: ліворуч від speedMeter
    local posX = speedMeter.speedBg.x
    local posY = speedMeter.speedBg.y
    
    -- Створюємо overlay з білою текстурою
    local whiteTexture = self.modDirectory .. "textures/white.png"
    self.backgroundOverlay = Overlay.new(whiteTexture, posX, posY, width, height)
    self.backgroundOverlay:setColor(0, 0, 0, 0.5) -- Чорний з 50% непрозорістю
end

---Оновлення даних HUD
---@param dt number Delta time
function HUD:update(dt)
    self.updateCount = self.updateCount + 1
    
    -- Оновлюємо дані кожен кадр
    self:updateData()
end

---Оновлює дані HUD з комбайна
function HUD:updateData()
    if not self.vehicle then
        return
    end
    
    local spec = self.vehicle.spec_rhm_Combine
    if not spec then
        return
    end
    
    -- Оновлюємо load з loadCalculator
    if spec.loadCalculator then
        self.data.load = spec.loadCalculator:getCurrentLoad()
        self.data.recommendedSpeed = spec.loadCalculator:getRecommendedSpeed()
        self.data.tonPerHour = spec.loadCalculator:getTonPerHour()
        
        -- Crop loss (якщо є)
        if spec.loadCalculator.getCropLoss then
            self.data.cropLoss = spec.loadCalculator:getCropLoss()
        end
    end
end


---Відображення HUD
function HUD:draw()
    self.drawCount = self.drawCount + 1
    
    -- Перевіряємо чи увімкнено HUD в налаштуваннях
    if not self.settings.showHUD then
        return
    end
    
    -- Перевірка чи overlay створений
    if not self.backgroundOverlay then
        return
    end
    
    -- Оновлюємо позицію overlay
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.speedMeter then
        local speedMeter = g_currentMission.hud.speedMeter
        local baseX = speedMeter.speedBg.x
        local baseY = speedMeter.speedBg.y
        
        -- Базове зміщення: ближче до speedMeter
        local offsetX = speedMeter:scalePixelToScreenWidth(-145)
        local offsetY = speedMeter:scalePixelToScreenHeight(15)
        
        -- Додаємо користувацьке зміщення з налаштувань
        if self.settings.hudOffsetX then
            offsetX = offsetX + speedMeter:scalePixelToScreenWidth(self.settings.hudOffsetX)
        end
        
        -- Встановлюємо позицію
        self.backgroundOverlay:setPosition(baseX + offsetX, baseY + offsetY)
    end
    
    -- Малюємо фон
    self.backgroundOverlay:render()
    
    -- Малюємо текст
    self:drawText()
end

function HUD:drawText()
    if not g_currentMission or not g_currentMission.hud or not g_currentMission.hud.speedMeter then
        return
    end
    
    local speedMeter = g_currentMission.hud.speedMeter
    local baseX = speedMeter.speedBg.x
    local baseY = speedMeter.speedBg.y
    
    -- Позиція тексту (відповідає позиції фону)
    local offsetX = speedMeter:scalePixelToScreenWidth(-145)
    local offsetY = speedMeter:scalePixelToScreenHeight(15)
    
    local textX = baseX + offsetX + speedMeter:scalePixelToScreenWidth(8)  -- Відступ від краю
    local textY = baseY + offsetY + speedMeter:scalePixelToScreenHeight(65) -- Ближче до верху
    
    local textSize = speedMeter:scalePixelToScreenHeight(13)  -- Однаковий розмір для всіх
    local lineHeight = speedMeter:scalePixelToScreenHeight(15) -- Відступ між рядками
    
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)  -- Без bold для всіх рядків
    
    -- Рядок 1: Load (навантаження) - з кольоровою градацією
    local loadColor
    if self.data.load < 70 then
        loadColor = {1, 1, 1, 1}      -- Білий (нормально)
    elseif self.data.load < 100 then
        loadColor = {1, 1, 0.4, 1}    -- Жовтий (попередження)
    else
        loadColor = {1, 0.4, 0.4, 1}  -- Червоний (небезпечно!)
    end
    
    setTextColor(loadColor[1], loadColor[2], loadColor[3], loadColor[4])
    renderText(textX, textY, textSize, string.format("Load: %.0f%%", self.data.load))
    
    -- Рядок 2: T/h (продуктивність) - завжди показується при зборі
    textY = textY - lineHeight
    if self.data.tonPerHour and self.data.tonPerHour > 0.01 then
        setTextColor(1, 1, 1, 0.95)  -- Білий
        renderText(textX, textY, textSize, string.format("T/h: %.1f", self.data.tonPerHour))
    else
        setTextColor(0.6, 0.6, 0.6, 0.8)  -- Сірий якщо ще не рахується
        renderText(textX, textY, textSize, "T/h: --")
    end
    
    -- Рядок 3: Crop Loss (тільки якщо функція увімкнена)
    if self.settings.enableCropLoss then
        textY = textY - lineHeight
        if self.data.cropLoss and self.data.cropLoss > 0 then
            setTextColor(1, 0.4, 0.4, 1) -- Червоний (втрати!)
            renderText(textX, textY, textSize, string.format("Loss: %.1f%%", self.data.cropLoss))
        else
            -- Якщо немає втрат - темно-сірий
            setTextColor(0.6, 0.6, 0.6, 0.8)
            renderText(textX, textY, textSize, "Loss: 0%")
        end
    end
    
    -- Рядок 4: Speed (тільки якщо enableSpeedLimit вимкнений)
    if not self.settings.enableSpeedLimit then
        -- Якщо LOSS не показується, Speed буде на місці LOSS
        if not self.settings.enableCropLoss then
            textY = textY - lineHeight
        end
        
        if self.data.recommendedSpeed then
            textY = textY - lineHeight
            local currentSpeed = 0
            if self.vehicle then
                currentSpeed = self.vehicle:getLastSpeed()
            end
            
            -- Вибираємо колір - білий базовий з градацією
            local speedColor
            if currentSpeed <= self.data.recommendedSpeed then
                speedColor = {1, 1, 1, 0.95}  -- Білий - нормально
            elseif currentSpeed <= self.data.recommendedSpeed * 1.1 then
                speedColor = {1, 0.9, 0.3, 1}  -- Жовтий - трохи швидко
            else
                speedColor = {1, 0.3, 0.3, 1}  -- Червоний - занадто швидко
            end
            
            setTextColor(speedColor[1], speedColor[2], speedColor[3], speedColor[4])
            renderText(textX, textY, textSize, string.format("Speed: %.1f / %.1f", currentSpeed, self.data.recommendedSpeed))
        end
    end
    
    -- Скидаємо налаштування
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

---Очистка ресурсів
function HUD:delete()
    if self.backgroundOverlay then
        self.backgroundOverlay:delete()
        self.backgroundOverlay = nil
    end
end

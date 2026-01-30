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
            -- Читаємо recommendedSpeed з синхронізованих даних (onReadUpdateStream)
            -- На сервері це значення встановлюється в onUpdateTick
            self.data.recommendedSpeed = spec.data.recommendedSpeed or 0
        end
    end
end

-- Викликається після завантаження місії
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
    local boxHeight = 90  -- ЗБІЛЬШЕНО для більших іконок
    
    -- Конвертуємо в екранні координати
    local width, height = speedMeter:scalePixelToScreenVector({boxWidth, boxHeight})
    
    -- Позиція: ліворуч від speedMeter
    local posX = speedMeter.speedBg.x
    local posY = speedMeter.speedBg.y
    
    -- Створюємо overlay з dds текстурою
    local whiteTexture = self.modDirectory .. "textures/hud_background.dds"
    self.backgroundOverlay = Overlay.new(whiteTexture, posX, posY, width, height)
    self.backgroundOverlay:setColor(0, 0, 0, 0.5) -- Чорний з 50% непрозорістю
    
    -- ПРАВИЛЬНО створюємо іконки - КВАДРАТНІ 32x32px
    local iconSize = speedMeter:scalePixelToScreenHeight(32) -- ЗБІЛЬШЕНО до 32px!
    local iconWidth = speedMeter:scalePixelToScreenWidth(32)  -- Квадратні!
    
    -- Створюємо іконки з КВАДРАТНИМИ пропорціями
    self.iconLoad = Overlay.new(self.modDirectory .. "textures/icon_load.dds", 0, 0, iconWidth, iconSize)
    self.iconProductivity = Overlay.new(self.modDirectory .. "textures/icon_productivity.dds", 0, 0, iconWidth, iconSize)
    self.iconLoss = Overlay.new(self.modDirectory .. "textures/icon_loss.dds", 0, 0, iconWidth, iconSize)
    self.iconSpeed = Overlay.new(self.modDirectory .. "textures/icon_speed.dds", 0, 0, iconWidth, iconSize)
    
    -- Встановлюємо білий колір для іконок
    if self.iconLoad then self.iconLoad:setColor(1, 1, 1, 1) end
    if self.iconProductivity then self.iconProductivity:setColor(1, 1, 1, 1) end
    if self.iconLoss then self.iconLoss:setColor(1, 1, 1, 1) end
    if self.iconSpeed then self.iconSpeed:setColor(1, 1, 1, 1) end
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
    
    -- Отримуємо швидкість (завжди синхронізовано грою)
    self.data.speed = self.vehicle:getLastSpeed() or 0
    
    -- Читаємо дані з spec.data (синхронізовано через multiplayer)
    if spec.data then
        self.data.load = spec.data.load or 0
        self.data.cropLoss = spec.data.cropLoss or 0
        self.data.tonPerHour = spec.data.tonPerHour or 0
        self.data.recommendedSpeed = spec.data.recommendedSpeed or 0
    end
end


---Відображення HUD
function HUD:draw()
    -- DEDICATED SERVER FIX: Don't render on server
    if not g_currentMission:getIsClient() then
        return
    end
    
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
        
        -- Встановлюємо позицію (для сумісності, але фон не малюємо)
        self.backgroundOverlay:setPosition(baseX + offsetX, baseY + offsetY)
    end
    
    -- НЕ малюємо старий загальний фон! Тепер кожен рядок має свій фон
    -- self.backgroundOverlay:render()  -- ВИДАЛЕНО - створював зайвий прямокутник
    
    -- Малюємо текст (з індивідуальними фонами для кожного рядка)
    self:drawText()
end

function HUD:drawText()
    if not self.data or not self.data.load then return end
    
    if not g_currentMission or not g_currentMission.hud or not g_currentMission.hud.speedMeter then
        return
    end
    
    local speedMeter = g_currentMission.hud.speedMeter
    
    local baseX = speedMeter.speedBg.x
    local baseY = speedMeter.speedBg.y
    
    -- Базове зміщення HUD
    local offsetX = speedMeter:scalePixelToScreenWidth(-160)  -- Трохи більше ліворуч (було -145)
    local offsetY = speedMeter:scalePixelToScreenHeight(50)    -- Опустити вниз (було 15, потім 10)
    
    -- Icons: 36x36px (квадратні)
    local iconSize = speedMeter:scalePixelToScreenHeight(36)
    local iconWidth = speedMeter:scalePixelToScreenWidth(36)
    
    local iconX = baseX + offsetX + speedMeter:scalePixelToScreenWidth(6)
    local textX = baseX + offsetX + speedMeter:scalePixelToScreenWidth(46)
    local startY = baseY + offsetY + speedMeter:scalePixelToScreenHeight(80)
    
    local textSize = speedMeter:scalePixelToScreenHeight(17)
    
    -- Розмір фону - має вміщувати іконку 36px + padding
    local bgPaddingX = speedMeter:scalePixelToScreenWidth(4)
    local bgPaddingY = speedMeter:scalePixelToScreenHeight(2)
    
    local rowBgWidth = speedMeter:scalePixelToScreenWidth(160)
    local rowBgHeight = iconSize + (bgPaddingY * 2)
    
    -- lineHeight = rowBgHeight БЕЗ зазору - фони стикаються
    local lineHeight = rowBgHeight
    
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    
    -- Функція для малювання фону та іконки
    local function drawRowWithIcon(icon, textY)
        -- Фон - ЦЕНТРУЄМО по іконці
        if self.backgroundOverlay then
            -- textY - це позиція baseline тексту
            -- Фон має бути centered по іконці
            local bgY = textY + textSize / 2 - rowBgHeight / 2  -- Центр по baseline тексту
            
            self.backgroundOverlay:setPosition(baseX + offsetX - bgPaddingX, bgY)
            self.backgroundOverlay:setDimension(rowBgWidth, rowBgHeight)
            self.backgroundOverlay:render()
        end
        
        -- Іконка (центрувати по вертикалі з текстом)
        if icon then
            local iconY = textY + textSize / 2 - iconSize / 2
            icon:setPosition(iconX, iconY)
            icon:render()
        end
    end
    
    local textY = startY
    
    -- Рядок 1: Load
    local loadColor
    if self.data.load < 70 then
        loadColor = {1, 1, 1, 1}
    elseif self.data.load < 100 then
        loadColor = {1, 1, 0.4, 1}
    else
        loadColor = {1, 0.4, 0.4, 1}
    end
    
    drawRowWithIcon(self.iconLoad, textY)
    setTextColor(loadColor[1], loadColor[2], loadColor[3], loadColor[4])
    renderText(textX, textY, textSize, string.format("%.0f%%", self.data.load))
    
    -- Рядок 2: T/h
    textY = textY - lineHeight
    drawRowWithIcon(self.iconProductivity, textY)
    
    if self.data.tonPerHour and self.data.tonPerHour > 0.01 then
        setTextColor(1, 1, 1, 0.95)
        local prodStr = string.format("%.1f t/h", self.data.tonPerHour)
        if UnitConverter then
             -- Use nil for fruitType (defaults to wheat) until we add it to data
            prodStr = UnitConverter.formatProductivity(self.data.tonPerHour, self.settings.unitSystem, nil)
        end
        renderText(textX, textY, textSize, prodStr)
    else
        setTextColor(0.6, 0.6, 0.6, 0.8)
        renderText(textX, textY, textSize, "--")
    end
    
    -- Рядок 3: Loss (якщо включений) АБО Speed (якщо налаштовано показувати)
    textY = textY - lineHeight
    
    if self.settings.enableCropLoss then
        -- Показуємо Loss
        drawRowWithIcon(self.iconLoss, textY)
        
        if self.data.cropLoss and self.data.cropLoss > 0 then
            setTextColor(1, 0.4, 0.4, 1)
            renderText(textX, textY, textSize, string.format("%.1f%%", self.data.cropLoss))
        else
            setTextColor(0.6, 0.6, 0.6, 0.8)
            renderText(textX, textY, textSize, "0%")
        end
        
        -- Рядок 4: Speed (якщо включений showSpeedometer)
        if self.settings.showSpeedometer and self.data.recommendedSpeed and self.data.recommendedSpeed > 0 then
            textY = textY - lineHeight
            drawRowWithIcon(self.iconSpeed, textY)
            
            local currentSpeed = 0
            if self.vehicle then
                currentSpeed = self.vehicle:getLastSpeed()
            end
            
            local speedColor
            if currentSpeed > (self.data.recommendedSpeed + 2) then
                speedColor = {1, 0.4, 0.4, 1}  -- червоний - дуже швидко
            elseif currentSpeed > self.data.recommendedSpeed then
                speedColor = {1, 1, 0.4, 1}  -- жовтий - трохи швидко
            else
                speedColor = {1, 1, 1, 1}  -- білий - ОК
            end
            
            local speedStr = string.format("%.1f / %.1f", currentSpeed, self.data.recommendedSpeed)
            if UnitConverter then
                local s1, suffix = UnitConverter.convertSpeed(currentSpeed, self.settings.unitSystem)
                local s2 = UnitConverter.convertSpeed(self.data.recommendedSpeed, self.settings.unitSystem)
                speedStr = string.format("%.1f / %.1f %s", s1, s2, suffix)
            end
            
            setTextColor(speedColor[1], speedColor[2], speedColor[3], speedColor[4])
            renderText(textX, textY, textSize, speedStr)
        end
    elseif self.settings.showSpeedometer and self.data.recommendedSpeed and self.data.recommendedSpeed > 0 then
        -- Loss вимкнений, але Speed потрібен - показуємо Speed на місці Loss (рядок 3)
        drawRowWithIcon(self.iconSpeed, textY)
        
        local currentSpeed = 0
        if self.vehicle then
            currentSpeed = self.vehicle:getLastSpeed()
        end
        
        local speedColor
        if currentSpeed > (self.data.recommendedSpeed + 2) then
            speedColor = {1, 0.4, 0.4, 1}
        elseif currentSpeed > self.data.recommendedSpeed then
            speedColor = {1, 1, 0.4, 1}
        else
            speedColor = {1, 1, 1, 1}
        end
        
        setTextColor(speedColor[1], speedColor[2], speedColor[3], speedColor[4])
        
        local speedStr
        if UnitConverter then
            local s1, suffix = UnitConverter.convertSpeed(currentSpeed, self.settings.unitSystem)
            local s2 = UnitConverter.convertSpeed(self.data.recommendedSpeed, self.settings.unitSystem)
            speedStr = string.format("%.1f / %.1f %s", s1, s2, suffix)
        else
            -- Fallback purely for safety
            speedStr = string.format("%.1f / %.1f", currentSpeed, self.data.recommendedSpeed)
        end
        
        renderText(textX, textY, textSize, speedStr)
    end
    -- Інакше НЕ малюємо зайвий рядок!
    
    -- Скидання alignment
    setTextAlignment(RenderText.ALIGN_LEFT)
end


---Очистка ресурсів
function HUD:delete()
    if self.backgroundOverlay then
        self.backgroundOverlay:delete()
        self.backgroundOverlay = nil
    end
end

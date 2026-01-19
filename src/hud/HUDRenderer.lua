---@class HUDRenderer
HUDRenderer = {}

-- Константи для кольорів
HUDRenderer.COLORS = {
    BACKGROUND = {0, 0, 0, 0.7},      -- Темний фон з прозорістю
    BORDER = {1, 1, 1, 0.3},          -- Світла рамка
    TEXT_WHITE = {1, 1, 1, 1},        -- Білий текст
    TEXT_GREEN = {0.2, 1, 0.2, 1},    -- Зелений текст (для активних значень)
    TEXT_YELLOW = {1, 1, 0.2, 1},     -- Жовтий текст (для попереджень)
    TEXT_RED = {1, 0.2, 0.2, 1}       -- Червоний текст (для критичних значень)
}

-- Константи для розмірів
HUDRenderer.SIZES = {
    PADDING = 0.005,                   -- Внутрішні відступи
    BORDER_WIDTH = 0.002,              -- Товщина рамки
    LINE_HEIGHT = 0.015                -- Висота рядка тексту
}

---Відображає текст
---@param text string Текст для відображення
---@param x number Позиція X (0-1)
---@param y number Позиція Y (0-1)
---@param size number Розмір шрифту
---@param color table Колір тексту {r, g, b, a}
---@param align string Вирівнювання ("left", "center", "right")
function HUDRenderer.drawText(text, x, y, size, color, align)
    align = align or "left"
    
    -- Перевірка параметрів
    if not text or text == "" then
        return
    end
    
    setTextColor(color[1], color[2], color[3], color[4])
    setTextBold(true)
    setTextAlignment(RenderText["ALIGN_" .. string.upper(align)])
    
    renderText(x, y, size, text)
    
    -- Скидаємо налаштування
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

---Обчислює ширину тексту
---@param text string Текст
---@param size number Розмір шрифту
---@return number Ширина тексту
function HUDRenderer.getTextWidth(text, size)
    setTextBold(true)
    local width = getTextWidth(size, text)
    setTextBold(false)
    return width
end

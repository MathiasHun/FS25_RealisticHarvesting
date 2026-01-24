---@class UnitConverter
-- Utility for converting between metric and imperial units
UnitConverter = {}

-- Unit system constants
UnitConverter.SYSTEM_METRIC = 1
UnitConverter.SYSTEM_IMPERIAL = 2
UnitConverter.SYSTEM_BUSHELS = 3  -- Imperial with bushels

-- Conversion coefficients
UnitConverter.KMH_TO_MPH = 0.621371
UnitConverter.TONNE_TO_TON = 1.10231
UnitConverter.HECTARE_TO_ACRE = 2.47105

-- Bushel conversion coefficients (tonnes to bushels per hour)
-- Based on standard USDA bushel weights for each crop
UnitConverter.BUSHEL_COEFFICIENTS = {
    -- Cereals
    [FruitType.WHEAT] = 36.76,         -- 27.2 kg (60 lbs)
    [FruitType.BARLEY] = 45.87,        -- 21.8 kg (48 lbs)
    [FruitType.OAT] = 68.97,           -- 14.5 kg (32 lbs)
    [FruitType.RICE] = 49.02,          -- 20.4 kg (45 lbs)
    [FruitType.RICELONGGRAIN] = 49.02, -- 20.4 kg (45 lbs)
    [FruitType.SORGHUM] = 39.37,       -- 25.4 kg (56 lbs)
    
    -- Oilseeds
    [FruitType.SOYBEAN] = 36.76,       -- 27.2 kg (60 lbs)
    [FruitType.CANOLA] = 44.05,        -- 22.7 kg (50 lbs)
    [FruitType.SUNFLOWER] = 88.50,     -- 11.3 kg (25 lbs)
    
    -- Row crops
    [FruitType.MAIZE] = 39.37,         -- 25.4 kg (56 lbs)
    [FruitType.COTTON] = 62.89,        -- 15.9 kg (35 lbs)
    
    -- Root crops (estimates, not standard)
    [FruitType.SUGARBEET] = 44.05,     -- ~22.7 kg (estimate)
    [FruitType.POTATO] = 36.76,        -- ~27.2 kg (estimate)
    
    -- Forage (no standard, using average)
    [FruitType.GRASS] = 40.0,          -- Approximate
    [FruitType.DRYGRASS] = 40.0,       -- Approximate
}

-- Default bushel coefficient (if crop not found)
UnitConverter.BUSHEL_DEFAULT = 36.76  -- Use wheat as default

---Convert speed based on unit system
---@param kmh number Speed in km/h
---@param system number Unit system (1=metric, 2=imperial, 3=bushels)
---@return number convertedValue
---@return string suffix
function UnitConverter.convertSpeed(kmh, system)
    if system == UnitConverter.SYSTEM_IMPERIAL or system == UnitConverter.SYSTEM_BUSHELS then
        return kmh * UnitConverter.KMH_TO_MPH, "mph"
    else
        return kmh, "km/h"
    end
end

---Convert productivity (mass per hour)
---@param tonnesPerHour number Productivity in t/h
---@param system number Unit system
---@param fruitType number|nil Current fruit type for bushel conversion
---@return number convertedValue
---@return string suffix
function UnitConverter.convertProductivity(tonnesPerHour, system, fruitType)
    if system == UnitConverter.SYSTEM_BUSHELS then
        -- Convert to bushels using crop-specific coefficient
        local coefficient = UnitConverter.BUSHEL_DEFAULT
        if fruitType and UnitConverter.BUSHEL_COEFFICIENTS[fruitType] then
            coefficient = UnitConverter.BUSHEL_COEFFICIENTS[fruitType]
        end
        return tonnesPerHour * coefficient, "bu/h"
    elseif system == UnitConverter.SYSTEM_IMPERIAL then
        return tonnesPerHour * UnitConverter.TONNE_TO_TON, "ton/h"
    else
        return tonnesPerHour, "t/h"
    end
end

---Convert area
---@param hectares number Area in hectares
---@param system number Unit system
---@return number convertedValue
---@return string suffix
function UnitConverter.convertArea(hectares, system)
    if system == UnitConverter.SYSTEM_IMPERIAL or system == UnitConverter.SYSTEM_BUSHELS then
        return hectares * UnitConverter.HECTARE_TO_ACRE, "ac"
    else
        return hectares, "ha"
    end
end

---Format speed with proper suffix
---@param kmh number Speed in km/h
---@param system number Unit system
---@return string Formatted string (e.g. "10.5 km/h" or "6.5 mph")
function UnitConverter.formatSpeed(kmh, system)
    local value, suffix = UnitConverter.convertSpeed(kmh, system)
    return string.format("%.1f %s", value, suffix)
end

---Format productivity
---@param tonnesPerHour number
---@param system number
---@param fruitType number|nil
---@return string
function UnitConverter.formatProductivity(tonnesPerHour, system, fruitType)
    local value, suffix = UnitConverter.convertProductivity(tonnesPerHour, system, fruitType)
    return string.format("%.1f %s", value, suffix)
end

---Format area
---@param hectares number
---@param system number
---@return string
function UnitConverter.formatArea(hectares, system)
    local value, suffix = UnitConverter.convertArea(hectares, system)
    return string.format("%.2f %s", value, suffix)
end

---Get unit system name
---@param system number
---@return string
function UnitConverter.getSystemName(system)
    if system == UnitConverter.SYSTEM_METRIC then
        return "Metric"
    elseif system == UnitConverter.SYSTEM_IMPERIAL then
        return "Imperial"
    elseif system == UnitConverter.SYSTEM_BUSHELS then
        return "Imperial (Bushels)"
    else
        return "Unknown"
    end
end

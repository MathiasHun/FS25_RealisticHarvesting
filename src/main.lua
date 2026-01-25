local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- Завантаження модулів
source(modDirectory .. "src/settings/SettingsManager.lua")
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SettingsGUI.lua")  -- Console commands for settings
source(modDirectory .. "src/utils/UIHelper.lua")
source(modDirectory .. "src/utils/UnitConverter.lua")  -- Unit conversion utility
source(modDirectory .. "src/settings/SettingsUI.lua")
source(modDirectory .. "src/hud/HUDRenderer.lua")
source(modDirectory .. "src/hud/HUD.lua")
source(modDirectory .. "src/logic/LoadCalculator.lua")  -- Розрахунок навантаження
source(modDirectory .. "src/rhm_Combine.lua")  -- Specialization для комбайна
source(modDirectory .. "src/RealisticHarvestManager.lua")

local rhm

local function isEnabled()
    return rhm ~= nil
end

-- Викликається після завантаження місії
local function loadedMission(mission, node)
    if not isEnabled() then
        return
    end
    
    if mission.cancelLoading then
        return
    end
    
    -- Init units safely
    if UnitConverter and UnitConverter.initBushelCoefficients then
        UnitConverter.initBushelCoefficients()
    end
    
    rhm:onMissionLoaded()
end

-- Викликається при завантаженні (створення об'єкта)
local function load(mission)
    if rhm == nil then
        rhm = RealisticHarvestManager.new(mission, modDirectory, modName)
        getfenv(0)["g_realisticHarvestManager"] = rhm
    end
end

-- Викликається при видаленні
local function unload()
    if rhm ~= nil then
        rhm:delete()
        rhm = nil
        getfenv(0)["g_realisticHarvestManager"] = nil
    end
end

-- Реєстрація specialization для комбайнів
local function validateTypes(manager)
    if manager.typeName == "vehicle" then
        -- Додаємо specialization
        g_specializationManager:addSpecialization("rhm_Combine", "rhm_Combine", modDirectory .. "src/rhm_Combine.lua", nil)
        
        -- Додаємо specialization до всіх комбайнів
        for typeName, typeEntry in pairs(g_vehicleTypeManager:getTypes()) do
            if SpecializationUtil.hasSpecialization(Combine, typeEntry.specializations) then
                g_vehicleTypeManager:addSpecialization(typeName, modName .. ".rhm_Combine")
            end
        end
    end
end

-- Реєстрація хуків
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

-- Додаємо update для оновлення HUD кожен кадр
FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if rhm then
        rhm:update(dt)
    end
end)

TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, validateTypes)

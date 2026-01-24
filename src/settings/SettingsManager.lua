---@class SettingsManager
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = g_currentModName
SettingsManager.XMLTAG = "realisticHarvestManager"

SettingsManager.defaultConfig = {
    difficulty = 2,  -- Normal
    showHUD = true,
    enableSpeedLimit = true,
    enableCropLoss = true,
    hudOffsetX = 0,    -- Horizontal offset
    hudOffsetY = 350,  -- Vertical offset
    unitSystem = 1     -- Metric
}

function SettingsManager.new()
    return setmetatable({}, SettingsManager_mt)
end

function SettingsManager:getSavegameXmlFilePath()
    if g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return ("%s/%s.xml"):format(g_currentMission.missionInfo.savegameDirectory, SettingsManager.MOD_NAME)
    end
    return nil
end

function SettingsManager:loadSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    if xmlPath and fileExists(xmlPath) then
        local xml = XMLFile.load("RHM_Config", xmlPath)
        if xml then
            settingsObject.difficulty = xml:getInt(self.XMLTAG..".difficulty", self.defaultConfig.difficulty)
            settingsObject.showHUD = xml:getBool(self.XMLTAG..".showHUD", self.defaultConfig.showHUD)
            settingsObject.enableSpeedLimit = xml:getBool(self.XMLTAG..".enableSpeedLimit", self.defaultConfig.enableSpeedLimit)
            settingsObject.enableCropLoss = xml:getBool(self.XMLTAG..".enableCropLoss", self.defaultConfig.enableCropLoss)
            settingsObject.hudOffsetX = xml:getInt(self.XMLTAG..".hudOffsetX", self.defaultConfig.hudOffsetX)
            settingsObject.hudOffsetY = xml:getInt(self.XMLTAG..".hudOffsetY", self.defaultConfig.hudOffsetY)
            settingsObject.unitSystem = xml:getInt(self.XMLTAG..".unitSystem", self.defaultConfig.unitSystem)
            xml:delete()
            return
        end
    end
    -- Fallback
    settingsObject.difficulty = self.defaultConfig.difficulty
    settingsObject.showHUD = self.defaultConfig.showHUD
    settingsObject.enableSpeedLimit = self.defaultConfig.enableSpeedLimit
    settingsObject.enableCropLoss = self.defaultConfig.enableCropLoss
    settingsObject.hudOffsetX = self.defaultConfig.hudOffsetX
    settingsObject.hudOffsetY = self.defaultConfig.hudOffsetY
    settingsObject.unitSystem = self.defaultConfig.unitSystem
end

function SettingsManager:saveSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    if not xmlPath then return end
    
    local xml = XMLFile.create("RHM_Config", xmlPath, self.XMLTAG)
    if xml then
        xml:setInt(self.XMLTAG..".difficulty", settingsObject.difficulty)
        xml:setBool(self.XMLTAG..".showHUD", settingsObject.showHUD)
        xml:setBool(self.XMLTAG..".enableSpeedLimit", settingsObject.enableSpeedLimit)
        xml:setBool(self.XMLTAG..".enableCropLoss", settingsObject.enableCropLoss)
        xml:setInt(self.XMLTAG..".hudOffsetX", settingsObject.hudOffsetX)
        xml:setInt(self.XMLTAG..".hudOffsetY", settingsObject.hudOffsetY)
        xml:setInt(self.XMLTAG..".unitSystem", settingsObject.unitSystem)
        xml:save()
        xml:delete()
    end
end
---@class SettingsManager
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = g_currentModName
SettingsManager.XMLTAG = "realisticHarvestManager"

-- Server-side settings (global, admin only)
SettingsManager.SERVER_SETTINGS = {
    "difficulty",
    "powerBoost",
    "enableSpeedLimit",
    "enableCropLoss"
}

-- Client-side settings (personal, per-player)
SettingsManager.CLIENT_SETTINGS = {
    "showHUD",
    "hudOffsetX",
    "hudOffsetY",
    "unitSystem"
}

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

-- Get path for server settings (in savegame directory)
function SettingsManager:getServerXmlFilePath()
    if g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return ("%s/%s_server.xml"):format(g_currentMission.missionInfo.savegameDirectory, SettingsManager.MOD_NAME)
    end
    return nil
end

-- Get path for client settings (in user profile directory)
function SettingsManager:getClientXmlFilePath()
    local userDir = getUserProfileAppPath()
    if userDir then
        return ("%s%s_client.xml"):format(userDir, SettingsManager.MOD_NAME)
    end
    return nil
end

-- Legacy method for backward compatibility
function SettingsManager:getSavegameXmlFilePath()
    return self:getServerXmlFilePath()
end

-- Load server settings (everyone reads)
function SettingsManager:loadServerSettings(settingsObject)
    local xmlPath = self:getServerXmlFilePath()
    if xmlPath and fileExists(xmlPath) then
        local xml = XMLFile.load("RHM_ServerConfig", xmlPath)
        if xml then
            for _, key in ipairs(self.SERVER_SETTINGS) do
                local xmlKey = self.XMLTAG.."."..key
                if key == "difficulty" or key == "powerBoost" or key == "hudOffsetX" or key == "hudOffsetY" or key == "unitSystem" then
                    settingsObject[key] = xml:getInt(xmlKey, self.defaultConfig[key])
                else
                    settingsObject[key] = xml:getBool(xmlKey, self.defaultConfig[key])
                end
            end
            xml:delete()
            return
        end
    end
    
    -- Fallback to defaults
    for _, key in ipairs(self.SERVER_SETTINGS) do
        settingsObject[key] = self.defaultConfig[key]
    end
end

-- Load client settings (each client reads their own)
function SettingsManager:loadClientSettings(settingsObject)
    local xmlPath = self:getClientXmlFilePath()
    if xmlPath and fileExists(xmlPath) then
        local xml = XMLFile.load("RHM_ClientConfig", xmlPath)
        if xml then
            for _, key in ipairs(self.CLIENT_SETTINGS) do
                local xmlKey = self.XMLTAG.."."..key
                if key == "hudOffsetX" or key == "hudOffsetY" or key == "unitSystem" then
                    settingsObject[key] = xml:getInt(xmlKey, self.defaultConfig[key])
                else
                    settingsObject[key] = xml:getBool(xmlKey, self.defaultConfig[key])
                end
            end
            xml:delete()
            return
        end
    end
    
    -- Fallback to defaults
    for _, key in ipairs(self.CLIENT_SETTINGS) do
        settingsObject[key] = self.defaultConfig[key]
    end
end

-- Main load method (loads both server and client settings)
function SettingsManager:loadSettings(settingsObject)
    -- Everyone loads server settings
    self:loadServerSettings(settingsObject)
    
    -- Each client loads their own client settings
    if g_currentMission:getIsClient() then
        self:loadClientSettings(settingsObject)
    end
end

-- Save server settings (only server)
function SettingsManager:saveServerSettings(settingsObject)
    local xmlPath = self:getServerXmlFilePath()
    if not xmlPath then return end
    
    local xml = XMLFile.create("RHM_ServerConfig", xmlPath, self.XMLTAG)
    if xml then
        for _, key in ipairs(self.SERVER_SETTINGS) do
            local xmlKey = self.XMLTAG.."."..key
            if key == "difficulty" or key == "powerBoost" then
                xml:setInt(xmlKey, settingsObject[key])
            else
                xml:setBool(xmlKey, settingsObject[key])
            end
        end
        xml:save()
        xml:delete()
    end
end

-- Save client settings (each client)
function SettingsManager:saveClientSettings(settingsObject)
    local xmlPath = self:getClientXmlFilePath()
    if not xmlPath then return end
    
    local xml = XMLFile.create("RHM_ClientConfig", xmlPath, self.XMLTAG)
    if xml then
        for _, key in ipairs(self.CLIENT_SETTINGS) do
            local xmlKey = self.XMLTAG.."."..key
            if key == "hudOffsetX" or key == "hudOffsetY" or key == "unitSystem" then
                xml:setInt(xmlKey, settingsObject[key])
            else
                xml:setBool(xmlKey, settingsObject[key])
            end
        end
        xml:save()
        xml:delete()
    end
end

-- Main save method (saves server and/or client settings based on context)
function SettingsManager:saveSettings(settingsObject)
    -- Server saves server settings
    if g_currentMission:getIsServer() then
        self:saveServerSettings(settingsObject)
    end
    
    -- Each client saves their own client settings
    if g_currentMission:getIsClient() then
        self:saveClientSettings(settingsObject)
    end
end
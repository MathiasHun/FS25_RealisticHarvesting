---@class SettingsSyncEvent
-- Network event for synchronizing server settings to all clients
SettingsSyncEvent = {}
local SettingsSyncEvent_mt = Class(SettingsSyncEvent, Event)

InitEventClass(SettingsSyncEvent, "SettingsSyncEvent")

function SettingsSyncEvent.emptyNew()
    local self = Event.new(SettingsSyncEvent_mt)
    return self
end

function SettingsSyncEvent.new(settings)
    local self = SettingsSyncEvent.emptyNew()
    
    -- Server-side settings to sync
    self.difficulty = settings.difficulty or 2
    self.powerBoost = settings:getPowerBoost() or 20
    self.enableSpeedLimit = settings.enableSpeedLimit
    self.enableCropLoss = settings.enableCropLoss
    
    return self
end

function SettingsSyncEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.difficulty)
    streamWriteUInt8(streamId, self.powerBoost)
    streamWriteBool(streamId, self.enableSpeedLimit)
    streamWriteBool(streamId, self.enableCropLoss)
end

function SettingsSyncEvent:readStream(streamId, connection)
    self.difficulty = streamReadUInt8(streamId)
    self.powerBoost = streamReadUInt8(streamId)
    self.enableSpeedLimit = streamReadBool(streamId)
    self.enableCropLoss = streamReadBool(streamId)
end

function SettingsSyncEvent:run(connection)
    -- Client receives server settings update
    if not g_currentMission:getIsServer() and g_realisticHarvestManager then
        local settings = g_realisticHarvestManager.settings
        if settings then
            settings.difficulty = self.difficulty
            settings.enableSpeedLimit = self.enableSpeedLimit
            settings.enableCropLoss = self.enableCropLoss
            
            print(string.format("RHM: Received server settings - Difficulty: %s, SpeedLimit: %s", 
                settings:getDifficultyName(), tostring(self.enableSpeedLimit)))
        end
    end
end

---@class SettingsSyncEvent
-- Network event for synchronizing server settings to all clients
SettingsSyncEvent = {}
local SettingsSyncEvent_mt = Class(SettingsSyncEvent, Event)

InitEventClass(SettingsSyncEvent, "RHM_SettingsSyncEvent")

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
    -- print(string.format("RHM: [Sync] Writing stream (Diff: %d, Speed: %s)", self.difficulty, tostring(self.enableSpeedLimit)))
    streamWriteUInt8(streamId, self.difficulty)
    streamWriteUInt8(streamId, self.powerBoost)
    streamWriteBool(streamId, self.enableSpeedLimit)
    streamWriteBool(streamId, self.enableCropLoss)
end

function SettingsSyncEvent:readStream(streamId, connection)
    -- print("RHM: [Sync] Reading stream...")
    self.difficulty = streamReadUInt8(streamId)
    self.powerBoost = streamReadUInt8(streamId)
    self.enableSpeedLimit = streamReadBool(streamId)
    self.enableCropLoss = streamReadBool(streamId)
    -- print(string.format("RHM: [Sync] Read stream (Diff: %d, Speed: %s)", self.difficulty, tostring(self.enableSpeedLimit)))
    
    self:run(connection)
end

function SettingsSyncEvent:run(connection)
    -- Case 1: Server receiving update from Client Admin
    if g_currentMission:getIsServer() then
        -- print("RHM: [Sync] Server received event from connection: " .. tostring(connection))
        
        if connection:getIsServer() then
            return
        end
        
        local settings = g_realisticHarvestManager.settings
        if settings then
            print(string.format("RHM: [Sync] Server APPLYING settings - Diff: %d, Speed: %s, Loss: %s", 
                self.difficulty, tostring(self.enableSpeedLimit), tostring(self.enableCropLoss)))
            
            -- Update server settings
            settings.difficulty = self.difficulty
            settings.enableSpeedLimit = self.enableSpeedLimit
            settings.enableCropLoss = self.enableCropLoss
            
            -- Save settings on server
            settings:save()
            
            -- Broadcast changes to ALL other clients
            g_server:broadcastEvent(self, nil, connection, nil)
            -- print("RHM: [Sync] Server rebroadcasted to others")
        else
            print("RHM: [Sync] ERROR - g_realisticHarvestManager.settings is nil!")
        end
        return
    end

    -- Case 2: Client receiving update from Server
    if g_realisticHarvestManager then
        local settings = g_realisticHarvestManager.settings
        if settings then
            settings.difficulty = self.difficulty
            settings.enableSpeedLimit = self.enableSpeedLimit
            settings.enableCropLoss = self.enableCropLoss
            
            -- print(string.format("RHM: [Sync] Client received update - Diff: %s, Speed: %s", 
            --    settings:getDifficultyName(), tostring(self.enableSpeedLimit)))
        end
    end
end

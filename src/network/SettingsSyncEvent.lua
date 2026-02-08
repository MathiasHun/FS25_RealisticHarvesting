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
    
    -- Server-side settings to sync (FIXED: use split difficulty)
    self.difficultyMotor = settings.difficultyMotor or 2
    self.difficultyLoss = settings.difficultyLoss or 2
    self.enableSpeedLimit = settings.enableSpeedLimit
    self.enableCropLoss = settings.enableCropLoss
    
    return self
end

function SettingsSyncEvent:writeStream(streamId, connection)
    -- print(string.format("RHM: [Sync] Writing stream (Motor: %d, Loss: %d, Speed: %s)", self.difficultyMotor, self.difficultyLoss, tostring(self.enableSpeedLimit)))
    streamWriteUInt8(streamId, self.difficultyMotor)
    streamWriteUInt8(streamId, self.difficultyLoss)
    streamWriteBool(streamId, self.enableSpeedLimit)
    streamWriteBool(streamId, self.enableCropLoss)
end

function SettingsSyncEvent:readStream(streamId, connection)
    -- print("RHM: [Sync] Reading stream...")
    self.difficultyMotor = streamReadUInt8(streamId)
    self.difficultyLoss = streamReadUInt8(streamId)
    self.enableSpeedLimit = streamReadBool(streamId)
    self.enableCropLoss = streamReadBool(streamId)
    -- print(string.format("RHM: [Sync] Read stream (Motor: %d, Loss: %d, Speed: %s)", self.difficultyMotor, self.difficultyLoss, tostring(self.enableSpeedLimit)))
    
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
            print(string.format("RHM: [Sync] Server APPLYING settings - Motor: %d, Loss: %d, Speed: %s, CropLoss: %s", 
                self.difficultyMotor, self.difficultyLoss, tostring(self.enableSpeedLimit), tostring(self.enableCropLoss)))
            
            -- Update server settings (FIXED: use split difficulty)
            settings.difficultyMotor = self.difficultyMotor
            settings.difficultyLoss = self.difficultyLoss
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
            -- FIXED: Apply split difficulty fields
            settings.difficultyMotor = self.difficultyMotor
            settings.difficultyLoss = self.difficultyLoss
            settings.enableSpeedLimit = self.enableSpeedLimit
            settings.enableCropLoss = self.enableCropLoss
            
            print(string.format("RHM: [Sync] Client received update - Motor: %d, Loss: %d, Speed: %s, CropLoss: %s", 
                self.difficultyMotor, self.difficultyLoss, tostring(self.enableSpeedLimit), tostring(self.enableCropLoss)))
        end
    end
end

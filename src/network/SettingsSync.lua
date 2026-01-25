---@class SettingsSync
-- Helper for synchronizing settings across network
SettingsSync = {}

---Send server settings to all clients
---@param settings Settings Server settings object
function SettingsSync:sendToClients(settings)
    if not g_currentMission:getIsServer() then
        return
    end
    
    -- Create and broadcast event
    local event = SettingsSyncEvent.new(settings)
    g_server:broadcastEvent(event)
    
    print("RHM: Broadcasting server settings to all clients")
end

---Receive server settings from server (called by event)
---@param eventData table Event data
function SettingsSync:receiveFromServer(eventData)
    if g_currentMission:getIsServer() then
        return
    end
    
    -- Settings are updated in SettingsSyncEvent:run()
    -- This is just a helper method if needed
end

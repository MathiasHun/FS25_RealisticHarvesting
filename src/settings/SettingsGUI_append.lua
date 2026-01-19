function SettingsGUI:consoleCommandMoveHUDLeft()
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        local settings = g_realisticHarvestManager.settings
        settings.hudOffsetX = math.max(-200, settings.hudOffsetX - 10)
        settings:save()
        
        return string.format("HUD Offset X: %d (moved LEFT)", settings.hudOffsetX)
    end
    
    return "Error: RHM not initialized"
end

function SettingsGUI:consoleCommandMoveHUDRight()
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        local settings = g_realisticHarvestManager.settings
        settings.hudOffsetX = math.min(200, settings.hudOffsetX + 10)
        settings:save()
        
        return string.format("HUD Offset X: %d (moved RIGHT)", settings.hudOffsetX)
    end
    
    return "Error: RHM not initialized"
end

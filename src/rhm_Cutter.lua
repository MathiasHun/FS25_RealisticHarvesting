-- rhm_Cutter: Налаштування для жаток (headers) для роздільного запуску

rhm_Cutter = {}

rhm_Cutter.debug = false

-- Запобігаємо автоматичному запуску молотарки при запуску жатки
-- І запобігаємо автоматичному запуску жатки при запуску комбайну!
function rhm_Cutter:onLoad(superFunc, savegame)
    superFunc(self, savegame)
    
    -- Перевіряємо чи увімкнена функція роздільного запуску
    local isIndependentLaunchEnabled = false
    if g_realisticHarvestManager and g_realisticHarvestManager.settings then
        isIndependentLaunchEnabled = g_realisticHarvestManager.settings.enableIndependentLaunch
    end
    
    local spec = self.spec_turnOnVehicle
    if spec and isIndependentLaunchEnabled then
        -- КРИТИЧНО ВАЖЛИВО: Вимикаємо авто-запуск через attacher vehicle
        spec.turnedOnByAttacherVehicle = false
    end
end

-- Перевизначаємо onLoad для всіх жаток
Cutter.onLoad = Utils.overwrittenFunction(Cutter.onLoad, rhm_Cutter.onLoad)

print("RHM: rhm_Cutter.lua loaded!")

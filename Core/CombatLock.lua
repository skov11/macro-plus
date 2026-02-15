local _, MMO = ...

-- Table of registered callbacks: key -> function(inCombat)
MMO.combatListeners = {}

-- Register a function to be called whenever combat state changes.
-- Use a unique string key so modules can register/unregister cleanly.
function MMO:RegisterCombatListener(key, callback)
    self.combatListeners[key] = callback
end

function MMO:UnregisterCombatListener(key)
    self.combatListeners[key] = nil
end

local function FireListeners(inCombat)
    for _, cb in pairs(MMO.combatListeners) do
        cb(inCombat)
    end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        MMO.inCombat = true
        FireListeners(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        MMO.inCombat = false
        FireListeners(false)
    end
end)

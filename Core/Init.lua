local AddonName, MMO = ...

-- Expose namespace globally for inter-module access and debugging
MacroPlus = MMO

MMO.isLoaded  = false
MMO.inCombat  = false

-- Central event frame for addon lifecycle
MMO.eventFrame = CreateFrame("Frame")
MMO.eventFrame:RegisterEvent("ADDON_LOADED")

MMO.eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == AddonName then
        MMO:OnLoad()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

function MMO:OnLoad()
    -- Initialize SavedVariables table if this is the first ever load
    if not MMO_GlobalDB then
        MMO_GlobalDB = {}
    end
    self.db = MMO_GlobalDB

    -- Slash command — UI toggle hooked up in Phase 2
    SLASH_MACROPLUS1 = "/mmo"
    SlashCmdList["MACROPLUS"] = function(msg)
        if self.ToggleUI then
            self:ToggleUI()
        else
            print("|cff00ccff[MacroPlus]|r UI not yet initialized.")
        end
    end

    self.isLoaded = true
    print("|cff00ccff[MacroPlus]|r v0.1.0 loaded.")
end

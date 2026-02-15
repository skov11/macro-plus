local AddonName, MMO = ...

-- Expose namespace globally for inter-module access and debugging
MacroPlus = MMO

MMO.isLoaded  = false
MMO.inCombat  = false

-- Shared button border style: adds a 1px dark border around any button
function MMO:StyleButton(btn)
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetFrameLevel(btn:GetFrameLevel() - 1)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
end

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
    SLASH_MACROPLUS1 = "/mp"
    SlashCmdList["MACROPLUS"] = function(msg)
        if self.ToggleUI then
            self:ToggleUI()
        else
            print("|cff00ccff[MacroPlus]|r UI not yet initialized.")
        end
    end

    -- Add button to the ESC Game Menu
    self:HookGameMenu()

    self.isLoaded = true
    print("|cff00ccff[MacroPlus]|r v0.1.0 loaded.")
end

function MMO:HookGameMenu()
    local menuBtn = CreateFrame("Button", "MacroPlusGameMenuButton", GameMenuFrame, "GameMenuButtonTemplate")
    menuBtn:SetText("|cff00ccffMacroPlus|r")
    menuBtn:SetScript("OnClick", function()
        HideUIPanel(GameMenuFrame)
        if self.ToggleUI then
            self:ToggleUI()
        end
    end)

    GameMenuFrame:HookScript("OnShow", function()
        -- Find the lowest visible button in the menu to anchor below it
        local lowestBtn, lowestY = nil, math.huge
        for _, child in ipairs({GameMenuFrame:GetChildren()}) do
            if child:IsObjectType("Button") and child ~= menuBtn and child:IsShown() and child:GetWidth() > 100 then
                local _, _, _, _, y = child:GetPoint(1)
                if y and y < lowestY then
                    lowestY = y
                    lowestBtn = child
                end
            end
        end

        -- Match size of an existing button
        if lowestBtn then
            menuBtn:SetSize(lowestBtn:GetWidth(), lowestBtn:GetHeight())
        end

        menuBtn:ClearAllPoints()
        if lowestBtn then
            menuBtn:SetPoint("TOP", lowestBtn, "BOTTOM", 0, -4)
        else
            menuBtn:SetPoint("BOTTOM", GameMenuFrame, "BOTTOM", 0, 18)
        end

        GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + menuBtn:GetHeight() + 8)
    end)
end

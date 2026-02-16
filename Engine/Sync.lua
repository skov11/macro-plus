local _, MMO = ...

local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

function MMO:CopyMacroToCurrentChar(macroData)
    if self.inCombat then
        print("|cff00ccff[MacroPlus]|r Cannot copy macros during combat.")
        return
    end

    if not macroData then return end

    local name = macroData.name or "Unnamed"
    -- Resolve icon through the shared helper so that nil, 0, empty
    -- string, or unexpected types are normalised to a safe value
    -- before reaching CreateMacro.
    local icon = MMO.ResolveIconForCreateMacro(macroData.icon)
    local body = macroData.body or ""
    local isAccount = macroData.isAccount

    -- Check available slots
    local numAccount, numCharacter = GetNumMacros()

    if isAccount then
        if numAccount >= MAX_ACCOUNT_MACROS then
            print("|cff00ccff[MacroPlus]|r No free account macro slots (" .. numAccount .. "/" .. MAX_ACCOUNT_MACROS .. ").")
            return
        end
    else
        if numCharacter >= MAX_CHARACTER_MACROS then
            print("|cff00ccff[MacroPlus]|r No free character macro slots (" .. numCharacter .. "/" .. MAX_CHARACTER_MACROS .. ").")
            return
        end
    end

    -- Create the macro
    -- perCharacter: true = character-specific, false/nil = account-wide
    local perCharacter = not isAccount
    local newIndex = CreateMacro(name, icon, body, perCharacter)

    if newIndex then
        print("|cff00ccff[MacroPlus]|r Copied '" .. name .. "' to current character (slot " .. newIndex .. ").")
    else
        print("|cff00ccff[MacroPlus]|r Failed to copy '" .. name .. "'.")
        return
    end

    -- Re-scrape to update DB
    MMO.ScrapeCurrentCharacter()

    -- Refresh sidebar
    if self.RefreshSidebar then
        self:RefreshSidebar()
    end
end

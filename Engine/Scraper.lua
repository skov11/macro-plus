local _, MMO = ...

-- WoW macro slot layout:
--   Account-wide macros : indices 1  .. MAX_ACCOUNT_MACROS
--   Character macros    : indices MAX_ACCOUNT_MACROS+1 .. MAX_ACCOUNT_MACROS+MAX_CHARACTER_MACROS
local MAX_ACCOUNT_MACROS   = 120
local MAX_CHARACTER_MACROS = 18

local function ScrapeCurrentCharacter()
    local realm    = GetRealmName()
    local charName = UnitName("player")
    if not realm or not charName then return end

    local numAccount, numCharacter = GetNumMacros()
    local macros = {}

    -- Account-wide macros
    for i = 1, numAccount do
        local name, icon, body = GetMacroInfo(i)
        if name and name ~= "" then
            macros[i] = {
                name      = name,
                icon      = icon,
                body      = body or "",
                isAccount = true,
            }
        end
    end

    -- Character-specific macros
    for i = 1, numCharacter do
        local idx = MAX_ACCOUNT_MACROS + i
        local name, icon, body = GetMacroInfo(idx)
        if name and name ~= "" then
            macros[idx] = {
                name      = name,
                icon      = icon,
                body      = body or "",
                isAccount = false,
            }
        end
    end

    -- Capture character metadata
    local _, className = UnitClass("player")  -- English class name (e.g., "WARRIOR", "MAGE")
    local faction = UnitFactionGroup("player") -- "Horde", "Alliance", or "Neutral"
    local classFile = className and className:lower() or "warrior"
    local _, raceFile = UnitRace("player")     -- e.g., "Human", "Orc", "NightElf"
    local sex = UnitSex("player")              -- 2 = male, 3 = female

    MMO:SetCharacterMacros(realm, charName, macros)
    MMO:SetCharacterMetadata(realm, charName, {
        class = classFile,
        faction = faction,
        race = raceFile,
        sex = sex,
    })
end

-- Expose so other modules (e.g. Sync) can trigger a re-scrape manually
MMO.ScrapeCurrentCharacter = ScrapeCurrentCharacter

-- Event listener
local scraperFrame = CreateFrame("Frame")
scraperFrame:RegisterEvent("PLAYER_LOGIN")
scraperFrame:RegisterEvent("UPDATE_MACROS")

scraperFrame:SetScript("OnEvent", function(self, event)
    -- Guard: database must be initialised before we can write
    if not MMO.isLoaded then return end
    ScrapeCurrentCharacter()
end)

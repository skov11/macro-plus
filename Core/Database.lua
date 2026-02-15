local _, MMO = ...

-- MMO_GlobalDB structure:
--
-- MMO_GlobalDB = {
--   [realm] = {
--     [charName] = {
--       macros   = {
--         [index] = { name, icon, body, isAccount }
--       },
--       lastSeen = <unix timestamp>,
--       class    = <class file name lowercase, e.g., "warrior">,
--       faction  = <"Horde", "Alliance", or "Neutral">,
--       race     = <race file name, e.g., "Human", "Orc", "NightElf">,
--       sex      = <2 = male, 3 = female>,
--     }
--   }
-- }

local function EnsureCharEntry(realm, charName)
    MMO.db[realm] = MMO.db[realm] or {}
    MMO.db[realm][charName] = MMO.db[realm][charName] or {
        macros   = {},
        lastSeen = 0,
    }
end

-- Write a full macro table for a character
function MMO:SetCharacterMacros(realm, charName, macros)
    EnsureCharEntry(realm, charName)
    self.db[realm][charName].macros   = macros
    self.db[realm][charName].lastSeen = time()
end

-- Read the macro table for a character (returns {} if not found)
function MMO:GetCharacterMacros(realm, charName)
    if self.db[realm] and self.db[realm][charName] then
        return self.db[realm][charName].macros
    end
    return {}
end

-- Returns a sorted list of all realm names in the DB
function MMO:GetAllRealms()
    local realms = {}
    for realm in pairs(self.db) do
        table.insert(realms, realm)
    end
    table.sort(realms)
    return realms
end

-- Returns a sorted list of character names for a given realm
function MMO:GetCharactersForRealm(realm)
    local chars = {}
    if self.db[realm] then
        for charName in pairs(self.db[realm]) do
            table.insert(chars, charName)
        end
        table.sort(chars)
    end
    return chars
end

-- Returns true if the given realm+charName matches the currently logged-in character
function MMO:IsCurrentCharacter(realm, charName)
    return realm == GetRealmName() and charName == UnitName("player")
end

-- Set character metadata (class, faction)
function MMO:SetCharacterMetadata(realm, charName, metadata)
    EnsureCharEntry(realm, charName)
    if metadata.class then
        self.db[realm][charName].class = metadata.class
    end
    if metadata.faction then
        self.db[realm][charName].faction = metadata.faction
    end
    if metadata.race then
        self.db[realm][charName].race = metadata.race
    end
    if metadata.sex then
        self.db[realm][charName].sex = metadata.sex
    end
end

-- Get character metadata (returns { class, faction, race, sex })
function MMO:GetCharacterMetadata(realm, charName)
    if self.db[realm] and self.db[realm][charName] then
        return {
            class = self.db[realm][charName].class,
            faction = self.db[realm][charName].faction,
            race = self.db[realm][charName].race,
            sex = self.db[realm][charName].sex,
        }
    end
    return {}
end

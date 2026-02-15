local _, MMO = ...

-- WoW Midnight macro condition database
-- argType: "none" = no argument, "keys" = modifier keys, "numeric" = number,
--          "text" = spell/item/etc name, "party_raid" = party or raid,
--          "mousebutton" = mouse button number

MMO.MacroConditions = {
    -- Modifier keys
    { name = "mod",             argType = "keys",        desc = "Modifier key is held down (shift, ctrl, alt)" },

    -- Combat state
    { name = "combat",          argType = "none",        desc = "Player is in combat" },
    { name = "stealth",         argType = "none",        desc = "Player is stealthed or invisible" },

    -- Target state
    { name = "exists",          argType = "none",        desc = "Target exists" },
    { name = "dead",            argType = "none",        desc = "Target is dead" },
    { name = "harm",            argType = "none",        desc = "Target is hostile (can attack)" },
    { name = "help",            argType = "none",        desc = "Target is friendly (can assist)" },

    -- Player state
    { name = "mounted",         argType = "none",        desc = "Player is mounted" },
    { name = "flying",          argType = "none",        desc = "Player is currently flying" },
    { name = "flyable",         argType = "none",        desc = "Player is in a flyable zone" },
    { name = "advflyable",      argType = "none",        desc = "Player can use dynamic/skyriding flight" },
    { name = "swimming",        argType = "none",        desc = "Player is swimming" },
    { name = "outdoors",        argType = "none",        desc = "Player is outdoors" },
    { name = "indoors",         argType = "none",        desc = "Player is indoors" },

    -- Class / spec
    { name = "form",            argType = "numeric",     desc = "Current shapeshift form number (0 = no form)" },
    { name = "stance",          argType = "numeric",     desc = "Current stance number (alias for form)" },
    { name = "spec",            argType = "numeric",     desc = "Active specialization (1-4)" },
    { name = "talent",          argType = "text",        desc = "Talent row/column or talent name is selected" },
    { name = "pvptalent",       argType = "text",        desc = "PvP talent name is selected" },
    { name = "known",           argType = "text",        desc = "Spell or ability is known/learned" },

    -- Group
    { name = "group",           argType = "party_raid",  desc = "Player is in a group (party or raid)" },

    -- Equipment
    { name = "equipped",        argType = "text",        desc = "Item type or name is equipped" },
    { name = "worn",            argType = "text",        desc = "Item type or name is equipped (alias for equipped)" },

    -- Channeling / casting
    { name = "channeling",      argType = "text",        desc = "Player is channeling (optionally a specific spell)" },

    -- Pet
    { name = "pet",             argType = "text",        desc = "Pet exists, or pet has specific name/family" },
    { name = "nopet",           argType = "none",        desc = "No pet is active" },

    -- Action bar
    { name = "bar",             argType = "numeric",     desc = "Current action bar page number" },
    { name = "bonusbar",        argType = "numeric",     desc = "Current bonus action bar number" },

    -- Mouse button
    { name = "btn",             argType = "mousebutton", desc = "Mouse button used to activate macro (1-5)" },

    -- Vehicle
    { name = "canexitvehicle",  argType = "none",        desc = "Player can exit current vehicle" },
    { name = "unithasvehicleui",argType = "none",        desc = "Target has a vehicle UI" },
    { name = "vehicleui",       argType = "none",        desc = "Player has vehicle UI active" },

    -- Misc
    { name = "cursor",          argType = "none",        desc = "Cursor is holding an item or spell" },
    { name = "actionbar",       argType = "numeric",     desc = "Current action bar page (alias for bar)" },
    { name = "overridebar",     argType = "none",        desc = "Override action bar is active" },
    { name = "possessbar",      argType = "none",        desc = "Possess bar is active (mind control)" },
    { name = "shapeshift",      argType = "none",        desc = "Player is in a shapeshift form" },
}

-- Valid unit targets for @ notation
MMO.MacroTargets = {
    "player", "target", "focus", "mouseover", "pet", "cursor",
    "party1", "party2", "party3", "party4",
    "raid1",  "raid2",  "raid3",  "raid4",  "raid5",
    "arena1", "arena2", "arena3",
    "boss1",  "boss2",  "boss3",  "boss4",  "boss5",
    "vehicle",
}

-- Build lookup table for condition validation
MMO.ConditionLookup = {}
for _, cond in ipairs(MMO.MacroConditions) do
    MMO.ConditionLookup[cond.name] = cond
    -- Also register "no" prefixed versions
    MMO.ConditionLookup["no" .. cond.name] = cond
end

-- Build target lookup
MMO.TargetLookup = {}
for _, t in ipairs(MMO.MacroTargets) do
    MMO.TargetLookup[t] = true
end

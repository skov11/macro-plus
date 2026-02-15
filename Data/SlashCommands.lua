local _, MMO = ...

-- Static database of WoW Midnight macro-relevant slash commands
-- Each entry: { cmd, aliases (table or nil), params ("required"/"optional"/"none"), desc, syntax }

MMO.SlashCommands = {
    {
        category = "Casting",
        commands = {
            { cmd = "/cast",            aliases = {"/use"},             params = "required", desc = "Cast a spell or use an item",                   syntax = "/cast [conditions] SpellName" },
            { cmd = "/castsequence",    aliases = nil,                  params = "required", desc = "Cast spells in order, advancing each press",    syntax = "/castsequence reset=target/combat/N Spell1, Spell2" },
            { cmd = "/castrandom",      aliases = {"/userandom"},       params = "required", desc = "Randomly cast one of several spells",           syntax = "/castrandom Spell1, Spell2, Spell3" },
            { cmd = "/cancelaura",      aliases = nil,                  params = "required", desc = "Cancel a buff on yourself",                     syntax = "/cancelaura BuffName" },
            { cmd = "/cancelform",      aliases = nil,                  params = "none",     desc = "Cancel current shapeshift form",                syntax = "/cancelform" },
            { cmd = "/stopmacro",       aliases = nil,                  params = "optional", desc = "Stop macro execution if conditions are met",    syntax = "/stopmacro [conditions]" },
            { cmd = "/stopspelltarget", aliases = nil,                  params = "none",     desc = "Stop spell targeting mode (green circle)",      syntax = "/stopspelltarget" },
            { cmd = "/stopcasting",     aliases = nil,                  params = "none",     desc = "Stop current cast or channel",                  syntax = "/stopcasting" },
        },
    },
    {
        category = "Targeting",
        commands = {
            { cmd = "/target",              aliases = {"/tar"},         params = "optional", desc = "Target a unit by name",                         syntax = "/target [conditions] UnitName" },
            { cmd = "/targetexact",         aliases = nil,              params = "required", desc = "Target a unit by exact name match",             syntax = "/targetexact UnitName" },
            { cmd = "/targetenemyplayer",   aliases = {"/tep"},         params = "none",     desc = "Target nearest enemy player",                  syntax = "/targetenemyplayer" },
            { cmd = "/targetfriendplayer",  aliases = {"/tfp"},         params = "none",     desc = "Target nearest friendly player",               syntax = "/targetfriendplayer" },
            { cmd = "/targetnearestenemy",  aliases = nil,              params = "none",     desc = "Target nearest visible enemy",                 syntax = "/targetnearestenemy" },
            { cmd = "/targetnearestfriend", aliases = nil,              params = "none",     desc = "Target nearest visible friendly",              syntax = "/targetnearestfriend" },
            { cmd = "/targetlastenemy",     aliases = {"/tle"},         params = "none",     desc = "Target last enemy you targeted",               syntax = "/targetlastenemy" },
            { cmd = "/targetlastfriend",    aliases = {"/tlf"},         params = "none",     desc = "Target last friendly you targeted",            syntax = "/targetlastfriend" },
            { cmd = "/assist",              aliases = {"/a"},           params = "optional", desc = "Target your target's target",                  syntax = "/assist [PlayerName]" },
            { cmd = "/focus",               aliases = nil,              params = "optional", desc = "Set focus target",                             syntax = "/focus [conditions] [UnitName]" },
            { cmd = "/clearfocus",          aliases = nil,              params = "none",     desc = "Clear focus target",                           syntax = "/clearfocus" },
            { cmd = "/cleartarget",         aliases = nil,              params = "none",     desc = "Clear current target",                         syntax = "/cleartarget" },
        },
    },
    {
        category = "Combat",
        commands = {
            { cmd = "/startattack",     aliases = nil,                  params = "optional", desc = "Start auto-attacking",                         syntax = "/startattack [conditions]" },
            { cmd = "/stopattack",      aliases = nil,                  params = "none",     desc = "Stop auto-attacking",                          syntax = "/stopattack" },
            { cmd = "/targetmarker",    aliases = {"/tm"},              params = "required", desc = "Set raid target marker on target",             syntax = "/targetmarker 1-8" },
            { cmd = "/worldmarker",     aliases = {"/wm"},              params = "required", desc = "Place world marker at position",               syntax = "/worldmarker 1-8" },
            { cmd = "/clearworldmarker",aliases = {"/cwm"},             params = "optional", desc = "Remove world markers",                        syntax = "/clearworldmarker [1-8]" },
        },
    },
    {
        category = "Pet",
        commands = {
            { cmd = "/petattack",       aliases = nil,                  params = "none",     desc = "Command pet to attack target",                 syntax = "/petattack [conditions]" },
            { cmd = "/petfollow",       aliases = nil,                  params = "none",     desc = "Command pet to follow you",                    syntax = "/petfollow" },
            { cmd = "/petstay",         aliases = nil,                  params = "none",     desc = "Command pet to stay in place",                 syntax = "/petstay" },
            { cmd = "/petpassive",      aliases = nil,                  params = "none",     desc = "Set pet to passive mode",                      syntax = "/petpassive" },
            { cmd = "/petdefensive",    aliases = nil,                  params = "none",     desc = "Set pet to defensive mode",                    syntax = "/petdefensive" },
            { cmd = "/petassist",       aliases = nil,                  params = "none",     desc = "Set pet to assist mode",                       syntax = "/petassist" },
            { cmd = "/petmoveto",       aliases = nil,                  params = "none",     desc = "Command pet to move to target location",       syntax = "/petmoveto" },
            { cmd = "/dismisspet",      aliases = nil,                  params = "none",     desc = "Dismiss active pet",                           syntax = "/dismisspet" },
        },
    },
    {
        category = "Equipment",
        commands = {
            { cmd = "/equip",           aliases = {"/eq"},              params = "required", desc = "Equip an item by name",                        syntax = "/equip ItemName" },
            { cmd = "/equipslot",       aliases = nil,                  params = "required", desc = "Equip an item to a specific slot",             syntax = "/equipslot SlotNumber ItemName" },
            { cmd = "/equipset",        aliases = nil,                  params = "required", desc = "Equip a saved equipment set",                  syntax = "/equipset SetName" },
        },
    },
    {
        category = "Chat",
        commands = {
            { cmd = "/say",             aliases = {"/s"},               params = "required", desc = "Send message to nearby players",               syntax = "/say message" },
            { cmd = "/yell",            aliases = {"/y"},               params = "required", desc = "Yell message to wider area",                   syntax = "/yell message" },
            { cmd = "/party",           aliases = {"/p"},               params = "required", desc = "Send message to party",                        syntax = "/party message" },
            { cmd = "/raid",            aliases = {"/ra"},              params = "required", desc = "Send message to raid",                         syntax = "/raid message" },
            { cmd = "/guild",           aliases = {"/g"},               params = "required", desc = "Send message to guild",                        syntax = "/guild message" },
            { cmd = "/whisper",         aliases = {"/w", "/tell"},      params = "required", desc = "Send private message to a player",             syntax = "/whisper PlayerName message" },
            { cmd = "/emote",           aliases = {"/em", "/me"},       params = "required", desc = "Perform a custom emote",                       syntax = "/emote does something cool" },
            { cmd = "/rw",              aliases = nil,                  params = "required", desc = "Send raid warning",                            syntax = "/rw message" },
            { cmd = "/i",               aliases = {"/instance"},        params = "required", desc = "Send message to instance group",               syntax = "/i message" },
        },
    },
    {
        category = "UI & System",
        commands = {
            { cmd = "/script",          aliases = {"/run"},             params = "required", desc = "Execute Lua code",                             syntax = "/run Lua_code_here" },
            { cmd = "/click",           aliases = nil,                  params = "required", desc = "Simulate a click on a named button",           syntax = "/click ButtonName" },
            { cmd = "/changeactionbar", aliases = nil,                  params = "required", desc = "Switch to a specific action bar page",         syntax = "/changeactionbar 1-6" },
            { cmd = "/swapactionbar",   aliases = nil,                  params = "required", desc = "Toggle between two action bar pages",          syntax = "/swapactionbar 1 2" },
            { cmd = "/console",         aliases = nil,                  params = "required", desc = "Set a console variable",                       syntax = "/console cvar value" },
            { cmd = "/reload",          aliases = {"/rl"},              params = "none",     desc = "Reload the UI",                                syntax = "/reload" },
        },
    },
    {
        category = "Movement",
        commands = {
            { cmd = "/dismount",        aliases = nil,                  params = "none",     desc = "Dismount from current mount",                  syntax = "/dismount" },
            { cmd = "/leavevehicle",    aliases = nil,                  params = "none",     desc = "Exit a vehicle",                               syntax = "/leavevehicle" },
            { cmd = "/follow",          aliases = {"/f"},               params = "optional", desc = "Follow targeted or named player",              syntax = "/follow [PlayerName]" },
            { cmd = "/sit",             aliases = nil,                  params = "none",     desc = "Sit down",                                     syntax = "/sit" },
            { cmd = "/stand",           aliases = nil,                  params = "none",     desc = "Stand up",                                     syntax = "/stand" },
        },
    },
    {
        category = "Macro Control",
        commands = {
            { cmd = "#showtooltip",     aliases = {"#show"},            params = "optional", desc = "Display a specific spell/item tooltip and icon", syntax = "#showtooltip [conditions] SpellName" },
        },
    },
}

-- Build a flat lookup table for quick command validation
-- Keyed by lowercase command (e.g., "/cast" -> entry)
MMO.SlashCommandLookup = {}

function MMO:BuildCommandLookup()
    for _, cat in ipairs(self.SlashCommands) do
        for _, entry in ipairs(cat.commands) do
            self.SlashCommandLookup[entry.cmd:lower()] = entry
            if entry.aliases then
                for _, alias in ipairs(entry.aliases) do
                    self.SlashCommandLookup[alias:lower()] = entry
                end
            end
        end
    end
end

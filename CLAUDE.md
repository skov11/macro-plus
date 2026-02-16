# Midnight Macro Overhaul (MMO)

## Project Overview

A WoW addon (Interface: 120000 / Midnight) that replaces the default Macro UI with:
- A cross-character macro library persisted via SavedVariables
- A modern IDE-style macro editor with syntax highlighting simulation
- A searchable slash-command reference (Command Encyclopedia)

## Tech Stack

- Language: Lua (WoW addon API)
- WoW Interface Version: 120000 (Midnight)
- Key APIs: `CreateFrame`, `EditMacro`, `CreateMacro`, `C_Spell.*`, `GetNumMacros`, `GetMacroInfo`, `GetMacroBody`
- SavedVariables: `MMO_GlobalDB`
- No external library dependencies (LibStub-free by design)

## UI Layout

```
┌─────────────────────────────────────────────────────────┐
│  [Shared]          │  Macro Editor                       │
│  [□][□] macros     │  ┌─────────────────────────────┐   │
│                    │  │  multi-line EditBox          │   │
│  [Char 1]          │  │  (IDE editor + overlay)      │   │
│  [□][□] macros     │  │                              │   │
│                    │  └─────────────────────────────┘   │
│  [Char 2]          │─────────────────────────────────── │
│  [□][□] macros     │  /commands                          │
│                    │  [/cast] [/use] [/target] ...       │
│  [+ more chars]    │  clickable → inserts into editor    │
└────────────────────┴────────────────────────────────────┘
```

- **Left panel (Sidebar)**: Scrollable list of characters grouped by realm, each showing their macro icon grid
- **Right top (Editor)**: Large multi-line EditBox with syntax highlight overlay and character counter
- **Right bottom (Command Panel)**: Clickable /command buttons; clicking inserts the command into the editor at cursor

## Project Structure

```
macro-plus/
├── MacroPlus.toc      ← Addon manifest
├── Core/
│   ├── Init.lua                   ← Addon entry point, namespace setup
│   ├── Database.lua               ← MMO_GlobalDB read/write accessors
│   └── CombatLock.lua             ← PLAYER_REGEN_DISABLED/ENABLED handlers
├── Engine/
│   ├── Scraper.lua                ← PLAYER_LOGIN + UPDATE_MACROS scraper
│   ├── ImportExport.lua           ← Serialize/deserialize macros, export/import dialogs
│   ├── Sharing.lua                ← Send/receive macros via addon messaging
│   ├── Sync.lua                   ← "Copy to Current Char" logic
│   ├── Parser.lua                 ← Macro syntax validation / dry-run parser
│   └── Shortener.lua              ← Macro body shortening utilities
├── UI/
│   ├── MainFrame.lua              ← Resizable outer window, layout anchor
│   ├── Sidebar.lua                ← Left panel: char list grouped by realm
│   ├── MacroGrid.lua              ← Icon grid per character (ScrollFrame)
│   ├── SearchBar.lua              ← Real-time name+body text filter
│   ├── Editor.lua                 ← EditBox + highlight overlay + counter
│   ├── ShareDialog.lua            ← Send dialog + accept/decline popup
│   ├── CommandPanel.lua           ← /commands buttons + tooltip + insert
│   ├── ConditionBuilder.lua       ← Visual condition group builder popup
│   └── MacroLibrary.lua           ← (5D) Class/spec macro library popup
└── Data/
    ├── SlashCommands.lua          ← Static Midnight slash command table
    ├── Conditions.lua             ← Macro condition definitions
    ├── SpecialCommands.lua        ← Special scripts, equipment slots, raid markers
    └── ClassMacros.lua            ← (5D) Curated class/spec macro definitions
```

## Phase Plan

| Phase | Files | Goal | Status |
|-------|-------|------|--------|
| 1 | TOC, Init, Database, Scraper, CombatLock | Data persists to WTF SavedVariables | ✅ Complete |
| 2 | MainFrame, Sidebar, MacroGrid, SearchBar | Full UI shell visible in-game | ✅ Complete |
| 3 | Editor, Sync | Live editing connected to `EditMacro` API | ✅ Complete |
| 4 | SlashCommands, CommandPanel, ConditionBuilder, Parser, Shortener | Command panel, condition builder, parser, shortener | ✅ Complete |
| 5A | ImportExport, Sidebar | Clipboard import/export of character macro sets | ✅ Complete |
| 5B | SpecialCommands, CommandPanel | Collapsible sections: Commands, Special, Slots, Markers, Target | ✅ Complete |
| 5C | Sharing, ShareDialog, Init, Editor | Send/receive macros via character name or BattleTag | ✅ Complete |
| 5D | ClassMacros, MacroLibrary, Editor | Class/spec-aware common macro library popup | Planned |
| 5E | SpecialCommands, CommandPanel | Command panel rework — match MacroToolkit feature parity | Planned |

---

## Current Progress

### ✅ Phase 1: Foundation (COMPLETE)
**Files:** `MacroPlus.toc`, `Core/Init.lua`, `Core/Database.lua`, `Core/CombatLock.lua`, `Engine/Scraper.lua`

**What's Working:**
- Addon loads on startup via `/mp` command
- Auto-scrapes all macros on `PLAYER_LOGIN` and `UPDATE_MACROS`
- Stores macro data to `MMO_GlobalDB` (persists to disk at `WTF/Account/<ACCOUNT>/SavedVariables/MacroPlus.lua`)
- Tracks both account-wide macros (indices 1-120) and character-specific macros (indices 121-138)
- Captures character metadata: class and faction
- Combat state tracking system ready for UI lockdown

**Data Structure:**
```lua
MMO_GlobalDB[realm][charName] = {
  macros = { [index] = { name, icon, body, isAccount } },
  lastSeen = <timestamp>,
  class = "warrior",
  faction = "Horde"
}
```

### ✅ Phase 2: UI Shell (COMPLETE)
**Files:** `UI/MainFrame.lua`, `UI/Sidebar.lua`, `UI/MacroGrid.lua`, `UI/SearchBar.lua`

**What's Working:**
- `/mp` opens a 900×600 resizable window
- Window auto-hides during combat (no taint risk)
- Draggable title bar, resize grip at bottom-right
- **Sidebar** (left panel):
  - "General" section at top showing account-wide macros with collapsible header
  - Characters grouped by realm with collapsible headers
  - Current character always appears first
  - Faction icon (Alliance/Horde) + race icon + class icon next to each name
  - Each character shows only their character-specific macros (5 per row, scrollable grid)
  - "New" button under General and current character sections
- **Search bar** at top of sidebar:
  - Real-time filter by macro name or body text
  - Applies across all characters and grids simultaneously
- **Macro icons** render in full color, clickable to load into editor

**Important Notes:**
- Each character must be logged in at least once and `/reload` to populate their data

---

### ✅ Phase 3: Editor & Sync (COMPLETE)
**Files:** `UI/Editor.lua`, `Engine/Sync.lua`

**What's Working:**
- **Editor (right panel, top section):**
  - Multi-line EditBox with syntax highlighting overlay (FontString)
  - Real-time character counter (0/255 display)
  - Header row: icon, name box, Change Icon, Conditions, Shorten, Save, Delete buttons
  - "Dry run" parser validates macro commands on text change
  - Save button → calls `EditMacro()` for current character only
  - Delete button with confirmation
  - Read-only mode for viewing alt macros with "Copy to Mine" button
- **Sync Logic:**
  - "Copy to Mine" button appears when viewing alt macros
  - Calls `CreateMacro()` to copy macro to logged-in character
  - Refreshes sidebar after copy

**Click Flow:**
- Click macro icon in sidebar → loads into editor
- Alt macro → read-only mode with "Copy to Mine"
- Current character macro → full edit mode

---

### ✅ Phase 4: Command Panel, Condition Builder, Parser, Shortener (COMPLETE)
**Files:** `Data/SlashCommands.lua`, `Data/Conditions.lua`, `UI/CommandPanel.lua`, `UI/ConditionBuilder.lua`, `Engine/Parser.lua`, `Engine/Shortener.lua`

**What's Working:**
- **Command Panel (right panel, bottom section):**
  - Scrollable button grid of slash commands grouped by category
  - Category dropdown filter + search box
  - Hover → tooltip shows syntax, aliases, and description
  - Click → inserts command at cursor in editor
- **Condition Builder:**
  - Visual popup for building macro condition groups (e.g., `[@mouseover,help,nodead]`)
  - Multi-group support with tab bar (add/remove groups)
  - Target dropdown + up to 5 condition rows with negation and argument fields
  - Live syntax preview + plain English summary translation
  - Auto-refreshes when selecting a different macro
  - Insert button pastes condition string into editor
- **Parser:** Validates macro syntax on each text change, shows inline error messages
- **Shortener:** Compresses macro body to save character count

---

### ✅ Phase 5A: Import/Export (COMPLETE)
**Files:** `Engine/ImportExport.lua`, `UI/Sidebar.lua`

**What's Working:**
- Export a character's macros to clipboard as a serialized `MPX1:` string
- Import macros from clipboard into General or current character
- Export button on every character header and General section
- Import button next to New buttons
- EditBox escaping handles WoW's automatic `|` → `||` doubling
- `ResolveIconForCreateMacro` helper ensures icons round-trip correctly
- Token-based escape/unescape prevents cross-contamination

### ✅ Phase 5B: Command Panel Collapsible Sections (COMPLETE)
**Files:** `Data/SpecialCommands.lua`, `UI/CommandPanel.lua`

**What's Working:**
- Single scrollable panel with 5 collapsible sections: Commands, Insert Special, Equipment Slots, Raid Markers, Target
- Commands expanded by default with inline category dropdown + search; all others collapsed
- Each section: clickable header with collapse arrow + gold label, full-width button grids when expanded
- Insert Special/Slots/Markers render as button grids; Target has inline text input + Insert button

### ✅ Phase 5C: Macro Sharing (COMPLETE)
**Files:** `Engine/Sharing.lua`, `UI/ShareDialog.lua`, `Core/Init.lua`, `UI/Editor.lua`

**What's Working:**
- Send macros to other MacroPlus users via character name or BattleTag
- Uses `C_ChatInfo.SendAddonMessage` (whisper, chunked at 245 bytes) and `BNSendGameData` (BattleTag)
- `MPLUS` addon message prefix registered on load
- Receiver gets Accept/Decline popup with macro icon, name, body preview, and sender name
- Incoming macro queue: multiple macros queued and shown one at a time
- BNet sender name resolved via `C_BattleNet.GetGameAccountInfoByID` + friend list iteration
- Combat safety: dialog auto-hides on combat start, re-shows when combat ends
- Share button visible for both current character and offline alt macros
- 30-second reassembly timeout for chunked messages

### 🚧 Phase 5D: Class/Spec Macro Library (PLANNED)
**Files:** `Data/ClassMacros.lua` (new), `UI/MacroLibrary.lua` (new), `UI/Editor.lua`, `MacroPlus.toc`

**Goal:** A popup window with curated, class/spec-aware macros that users can browse and one-click copy to their character.

**Data Structure (`Data/ClassMacros.lua`):**
```lua
MMO.ClassMacros = {
    WARRIOR = {
        Arms = {
            { name = "Bladestorm Focus", body = "/cast [@focus] Bladestorm", desc = "Bladestorm on focus target", tags = {"PvP"} },
        },
        Fury = { ... },
        Protection = { ... },
        General = { ... },  -- class-wide macros, any spec
    },
    PRIEST = { ... },
    -- ...
}
```

**UI (`UI/MacroLibrary.lua`):**
- Popup frame (~500×450, centered, movable, FULLSCREEN_DIALOG)
- **Left column:** Class list (auto-detects current class, highlights it, shows all classes)
- **Top bar:** Spec tabs (populated dynamically from selected class) + "General" tab + PvE/PvP filter toggle
- **Body:** Scrollable list of macro cards, each showing: name, description, truncated body preview, tags
- **Per-card buttons:** "Copy to Mine" → calls `CreateMacro()`, "Preview" → loads into editor read-only
- **Search bar** at top for filtering by name/body/description

**Editor Integration:**
- Add "Library" button to editor header row (after Share button)
- Button opens the MacroLibrary popup
- Clicking "Preview" in library loads macro into editor in read-only preview mode

**Data Population:**
- Curated from `scrape/recommended_macros.json` (already scraped from Icy Veins)
- Static data shipped with the addon — no runtime fetching
- Structured by class → spec → macro entries

---

### 🚧 Phase 5E: Command Panel Rework (PLANNED)
**Files:** `Data/SpecialCommands.lua`, `UI/CommandPanel.lua`
**Reference:** `research/macrotoolkit-insert-special-slot-report.md`

**Goal:** Rework the bottom command panel to match MacroToolkit's feature parity while keeping MacroPlus's superior design (self-contained `/run` snippets, no addon dependency, collapsible sections).

#### 5E-1: Character Limit Pre-Check on Insert
**File:** `UI/CommandPanel.lua` — `InsertAtCursor()`

Current `InsertAtCursor()` blindly inserts without checking the 255-char limit. Add a pre-check:
```lua
function MMO:InsertAtCursor(text)
    local eb = _G["MacroPlusEditBox"]
    if not eb or not eb:IsEnabled() then return end
    local currentLen = strlenutf8(eb:GetText())
    local insertLen = strlenutf8(text)
    if currentLen + insertLen > 255 then
        print("|cff00ccff[MacroPlus]|r Not enough space. Command needs "
              .. insertLen .. " chars (" .. (255 - currentLen) .. " available).")
        return
    end
    eb:SetFocus()
    eb:Insert(text)
end
```

#### 5E-2: Auto-Append Newline for Special Scripts
**File:** `UI/CommandPanel.lua` — `RenderSpecialContent()` OnClick handler

Special scripts are complete macro lines. After inserting, append `\n` if room:
```lua
btn:SetScript("OnClick", function()
    local script = item.script
    local eb = _G["MacroPlusEditBox"]
    if eb then
        local remaining = 255 - strlenutf8(eb:GetText())
        if strlenutf8(script) + 1 <= remaining then
            script = script .. "\n"
        end
    end
    MMO:InsertAtCursor(script)
end)
```

#### 5E-3: Localized Equipment Slot Names
**File:** `Data/SpecialCommands.lua` — `MMO.EquipmentSlots`

Replace hardcoded English strings with WoW's built-in `_G.INVTYPE_*` globals for automatic localization:
```lua
MMO.EquipmentSlots = {
    { name = _G.INVTYPE_HEAD,                                slotNum = 1 },
    { name = _G.INVTYPE_NECK,                                slotNum = 2 },
    { name = _G.INVTYPE_SHOULDER,                            slotNum = 3 },
    { name = _G.INVTYPE_BODY,                                slotNum = 4 },
    { name = _G.INVTYPE_CHEST,                               slotNum = 5 },
    { name = _G.INVTYPE_WAIST,                               slotNum = 6 },
    { name = _G.INVTYPE_LEGS,                                slotNum = 7 },
    { name = _G.INVTYPE_FEET,                                slotNum = 8 },
    { name = _G.INVTYPE_WRIST,                               slotNum = 9 },
    { name = _G.INVTYPE_HAND,                                slotNum = 10 },
    { name = format("%s 1", _G.INVTYPE_FINGER),              slotNum = 11 },
    { name = format("%s 2", _G.INVTYPE_FINGER),              slotNum = 12 },
    { name = format("%s 1", _G.INVTYPE_TRINKET),             slotNum = 13 },
    { name = format("%s 2", _G.INVTYPE_TRINKET),             slotNum = 14 },
    { name = _G.INVTYPE_CLOAK,                               slotNum = 15 },
    { name = _G.INVTYPE_WEAPONMAINHAND,                      slotNum = 16 },
    { name = _G.INVTYPE_WEAPONOFFHAND,                       slotNum = 17 },
    { name = _G.INVTYPE_RANGED or "Ranged",                  slotNum = 18 },
    { name = _G.INVTYPE_TABARD,                              slotNum = 19 },
}
```

#### 5E-4: Add Missing Special Scripts
**File:** `Data/SpecialCommands.lua` — `MMO.SpecialScripts`

Add scripts from MacroToolkit that are missing, using Midnight-compatible APIs and self-contained `/run` snippets. Also add a `desc` field for human-readable tooltips:
```lua
-- Add to existing table:
{ name = "Random mount",       script = "/run C_MountJournal.SummonByID(0)",
  desc = "Summon a random favourite mount" },
{ name = "Eject passenger",   script = "/run for s=1,2 do if CanEjectPassengerFromSeat(s) then EjectPassengerFromSeat(s) end end",
  desc = "Eject passengers from your vehicle" },
{ name = "Cancel form",       script = "/cancelform",
  desc = "Cancel current shapeshift/stance form" },
{ name = "Toggle auto-loot",  script = '/run SetCVar("autoLootDefault",1-GetCVar("autoLootDefault"))',
  desc = "Toggle automatic looting on/off" },
{ name = "Reload UI",         script = "/reload",
  desc = "Reload the user interface" },
```

Also add `desc` field to all existing entries for better tooltips (currently tooltip shows raw script text).

Update deprecated scripts:
- **Toggle cloak/helm**: `ShowCloak()`/`ShowHelm()` are removed in Midnight. Research `C_Transmog` alternative or remove these entries.

#### 5E-5: Tooltip Improvements for Special Scripts
**File:** `UI/CommandPanel.lua` — `RenderSpecialContent()` tooltip handler

Currently the tooltip shows the raw `/run` script text. Change to show:
- **Line 1:** Script name (title color)
- **Line 2:** Human-readable description (from new `desc` field)
- **Line 3:** Blank separator
- **Line 4:** "Inserts:" label
- **Line 5:** The actual script text (gold, word-wrapped)
- **Line 6:** Character count: "Length: X characters"

```lua
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(item.name, 0.4, 0.8, 1)
    if item.desc then
        GameTooltip:AddLine(item.desc, 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Inserts:", 0.5, 0.8, 0.5)
    GameTooltip:AddLine(item.script, 1, 0.82, 0, true)
    GameTooltip:AddLine("Length: " .. #item.script .. " characters", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
```

#### 5E-6: Equipment Slot Tooltip — Show Equipped Item
**File:** `UI/CommandPanel.lua` — `RenderSlotsContent()` tooltip handler

Enhance slot tooltips to show what item the player currently has equipped in that slot:
```lua
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(slot.name, 0.4, 0.8, 1)
    GameTooltip:AddLine("Slot " .. slot.slotNum .. "  →  /use " .. slot.slotNum, 1, 1, 1)
    local itemLink = GetInventoryItemLink("player", slot.slotNum)
    if itemLink then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Equipped: " .. itemLink, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end)
```

#### 5E-7: Raid Markers — Insert as `/tm` Command
**File:** `UI/CommandPanel.lua` — `RenderMarkersContent()` OnClick handler

Currently markers insert the chat token (e.g. `{skull}`). More useful would be to also offer the `/tm` (targetmarker) syntax. Add a tooltip showing both options, and default click inserts `/tm 8` (the numeric marker ID for use in macros like `/tm 8` to skull the target).

#### Summary of 5E Changes

| Sub-step | File(s) | Change |
|----------|---------|--------|
| 5E-1 | CommandPanel.lua | 255-char limit pre-check in `InsertAtCursor()` |
| 5E-2 | CommandPanel.lua | Auto-append `\n` for special script insertions |
| 5E-3 | SpecialCommands.lua | Localized slot names via `_G.INVTYPE_*` |
| 5E-4 | SpecialCommands.lua | Add 5 missing scripts + `desc` field + deprecation cleanup |
| 5E-5 | CommandPanel.lua | Improved special script tooltips with description + char count |
| 5E-6 | CommandPanel.lua | Slot tooltips show currently equipped item |
| 5E-7 | CommandPanel.lua | Raid markers insert `/tm N` command by default |

---

## Architecture Notes

- **Combat Lockdown**: Use `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` events to disable/hide the editor and all macro-write operations. All UI is plain `Frame` (not SecureFrame) to avoid taint.
- **Alt macros are read-only**: `EditMacro` / `CreateMacro` only called for the currently logged-in character. Data for other alts is display-only, sourced from `MMO_GlobalDB`.
- **Syntax highlighting**: A read-only `FontString` overlay rendered on top of the EditBox, refreshed on `OnTextChanged`. Highlights `/cast`, `/use`, `/target` and conditionals like `[help,nodead]` using color escape codes.
- **Icon resolution**: Use `C_Spell.GetSpellTexture` and `C_Spell.GetOverrideSpell` instead of deprecated `GetSpellInfo`.
- **Character counter**: Real-time `0/255` display tied to `OnTextChanged`; can be extended for "Extended Macro" support via secure action button swapping.
- **Scraper fires on**: `PLAYER_LOGIN` and `UPDATE_MACROS`. Stores data as `MMO_GlobalDB[realm][charName][index] = { name, icon, body }`. Also captures character metadata (class, faction).
- **Account vs Character macros**: UI displays "Shared (Account-wide)" section at top showing all account macros once. Each character section shows only their character-specific macros (filtered by `isAccount` flag).
- **Character list sorting**: Current character always appears first in their realm, then alphabetically.
- **Class/Faction icons**: Sidebar displays faction icon (Alliance/Horde) and class icon next to each character name using WoW's built-in icon assets.

## Development Setup

1. Copy `.env-example` to `.env` and set `WOW_ADDONS_PATH` to your local WoW AddOns folder
2. Run `./deploy.sh` to push addon files to WoW — this backs up the previous version first
3. Enable **MacroPlus** from the WoW character select screen
4. Use `/reload` in-game to reload the UI after changes
5. Check `SavedVariables` at `WTF/Account/<ACCOUNT>/SavedVariables/MacroPlus.lua`

### deploy.sh behaviour
- On first run: creates `MacroPlus/` in your AddOns folder and copies files
- On subsequent runs: backs up existing files to `MacroPlus/backups/<timestamp>/`, cleans the folder, then deploys fresh

## Common Commands

```
/mp           → Toggle the Macro Hub window
/reload       → Reload UI (in-game, for testing changes)
```

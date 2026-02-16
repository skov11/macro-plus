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
│   ├── Sync.lua                   ← "Copy to Current Char" logic
│   ├── Parser.lua                 ← Macro syntax validation / dry-run parser
│   └── Shortener.lua              ← Macro body shortening utilities
├── UI/
│   ├── MainFrame.lua              ← Resizable outer window, layout anchor
│   ├── Sidebar.lua                ← Left panel: char list grouped by realm
│   ├── MacroGrid.lua              ← Icon grid per character (ScrollFrame)
│   ├── SearchBar.lua              ← Real-time name+body text filter
│   ├── Editor.lua                 ← EditBox + highlight overlay + counter
│   ├── CommandPanel.lua           ← /commands buttons + tooltip + insert
│   └── ConditionBuilder.lua       ← Visual condition group builder popup
└── Data/
    ├── SlashCommands.lua          ← Static Midnight slash command table
    └── Conditions.lua             ← Macro condition definitions
```

## Phase Plan

| Phase | Files | Goal | Status |
|-------|-------|------|--------|
| 1 | TOC, Init, Database, Scraper, CombatLock | Data persists to WTF SavedVariables | ✅ Complete |
| 2 | MainFrame, Sidebar, MacroGrid, SearchBar | Full UI shell visible in-game | ✅ Complete |
| 3 | Editor, Sync | Live editing connected to `EditMacro` API | ✅ Complete |
| 4 | SlashCommands, CommandPanel, ConditionBuilder, Parser, Shortener | Command panel, condition builder, parser, shortener | ✅ Complete |
| 5A | ImportExport, Sidebar | Clipboard import/export of character macro sets | Planned |
| 5B | SpecialCommands, CommandPanel | Insert Special scripts & equipment slot references | Planned |
| 5C | Sharing, ShareDialog, Init, Editor | Send/receive macros via character name or BattleTag | Planned |
| 5D | ClassMacros, MacroLibrary, Editor | Class/spec-aware common macro library popup | Planned |

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

### 🚧 Phase 5: Advanced Features (PLANNED)
See plan file at `.claude/plans/golden-brewing-tide.md` for full details.

**5A — Import/Export:**
- Export a character's macros to clipboard as a serialized string
- Import macros from clipboard into General or current character
- Export button on every character, Import button next to New buttons

**5B — Insert Special / Insert Slot:**
- Split bottom command panel into two columns
- Left: existing slash commands. Right: special script snippets + equipment slot references
- One-click insert of `/run` scripts and equipment slot numbers

**5C — Macro Sharing:**
- Send macros to other MacroPlus users via character name or BattleTag
- Uses WoW addon messaging (`C_ChatInfo.SendAddonMessage` / `BNSendGameData`)
- Receiver gets Accept/Decline popup with macro preview

**5D — Commonly Used Macros:**
- Class/spec-aware macro library popup with PvE/PvP filter
- Curated macros with descriptions and one-click copy to character
- Data populated from external scraping (in progress)

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

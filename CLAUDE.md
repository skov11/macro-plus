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
│   └── Sync.lua                   ← "Copy to Current Char" logic
├── UI/
│   ├── MainFrame.lua              ← Resizable outer window, layout anchor
│   ├── Sidebar.lua                ← Left panel: char list grouped by realm
│   ├── MacroGrid.lua              ← Icon grid per character (ScrollFrame)
│   ├── SearchBar.lua              ← Real-time name+body text filter
│   ├── Editor.lua                 ← EditBox + highlight overlay + counter
│   └── CommandPanel.lua           ← /commands buttons + tooltip + insert
└── Data/
    └── SlashCommands.lua          ← Static Midnight slash command table
```

## Phase Plan

| Phase | Files | Goal | Status |
|-------|-------|------|--------|
| 1 | TOC, Init, Database, Scraper, CombatLock | Data persists to WTF SavedVariables | ✅ Complete |
| 2 | MainFrame, Sidebar, MacroGrid, SearchBar | Full UI shell visible in-game | ✅ Complete |
| 3 | Editor, Sync | Live editing connected to `EditMacro` API | Pending |
| 4 | SlashCommands, CommandPanel | Encyclopedia with insert-on-click | Pending |

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

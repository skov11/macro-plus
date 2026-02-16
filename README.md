# Macro Plus

A World of Warcraft addon for **Midnight (Interface: 120000)** that replaces the default Macro UI with a cross-character macro library, a modern IDE-style editor, and a searchable slash-command encyclopedia.

---

## Features

### Live Now
- **Cross-Character Library** — Browse and copy macros from all your alts, stored persistently across sessions via `SavedVariables`
- **Account vs Character Separation** — Account-wide macros shown in "General" section, character-specific macros under each character
- **Character Metadata** — Faction, race, and class icons displayed next to each character name; current character always appears first
- **Collapsible Sidebar** — Realm and character sections collapse/expand; only current realm and character auto-expand
- **Real-Time Search** — Filter macros by name or body text across all characters simultaneously
- **IDE-Style Editor** — Multi-line editor with simulated syntax highlighting for slash commands and conditionals, plus a real-time 0/255 character counter
- **Save / Delete / Copy** — Save edits to current character, delete macros with confirmation, or copy any alt's macro to your character
- **Condition Builder** — Visual popup for building complex condition groups (e.g., `[@mouseover,help,nodead]`) with multi-group tabs, a live syntax preview, and a plain English summary
- **Macro Parser** — Real-time validation of macro syntax with inline error display
- **Macro Shortener** — Compress macro body to save character count
- **Command Encyclopedia** — Searchable reference of every valid slash command in Midnight, with category filters, tooltips, and click-to-insert
- **Create New Macros** — "New" button for both account-wide and character-specific slots
- **Combat Safe** — All editing is automatically disabled during combat to prevent taint errors
- **Midnight Compatible** — Uses `C_Spell` APIs and targets Interface `120000`

### Coming Soon
- **Import/Export** — Export a character's full macro set to clipboard and import on another character
- **Insert Special / Insert Slot** — One-click insertion of common script snippets and equipment slot references
- **Macro Sharing** — Send macros to other MacroPlus users via character name or BattleTag
- **Common Macro Library** — Class/spec-aware curated macros for PvP and PvE with one-click copy

---

## Installation

1. Clone this repository
2. Copy `.env-example` to `.env` and set your WoW AddOns path:
   ```
   WOW_ADDONS_PATH="/path/to/World of Warcraft/_retail_/Interface/AddOns"
   ```
3. Run the deploy script to push the addon to your AddOns folder:
   ```bash
   ./deploy.sh
   ```
4. Launch WoW and enable **MacroPlus** on the character select screen
5. Log in and type `/mp` to open the Macro Hub

> Each deploy automatically backs up the previous version to `MacroPlus/backups/<timestamp>/` before deploying.

---

## Usage

| Command | Action |
|---------|--------|
| `/mp` | Toggle the Macro Hub window |

- **Click a character** in the sidebar to expand/collapse their macros
- **Click a macro icon** to load it into the editor
- **Edit and save** — changes apply only to your current character
- **Copy to Mine** — appears in read-only mode when viewing an alt's macro
- **Conditions button** — opens the visual condition builder popup
- **Shorten button** — compresses macro body to save characters
- **Click a /command button** in the encyclopedia to insert it at the cursor
- **New button** — create new macros in General (account-wide) or character-specific slots

---

## Project Structure

```
MacroPlus/
├── MacroPlus.toc
├── Core/
│   ├── Init.lua              # Addon entry point, namespace
│   ├── Database.lua          # MMO_GlobalDB accessors
│   └── CombatLock.lua        # Combat lockdown handling
├── Engine/
│   ├── Scraper.lua           # Macro data collection on login
│   ├── Sync.lua              # Copy-to-character logic
│   ├── Parser.lua            # Macro syntax validation
│   └── Shortener.lua         # Macro body compression
├── UI/
│   ├── MainFrame.lua         # Main resizable window
│   ├── Sidebar.lua           # Character list by realm
│   ├── MacroGrid.lua         # Icon grid (ScrollFrame)
│   ├── SearchBar.lua         # Real-time macro filter
│   ├── Editor.lua            # IDE-style EditBox + header
│   ├── CommandPanel.lua      # Slash command encyclopedia
│   └── ConditionBuilder.lua  # Visual condition group builder
└── Data/
    ├── SlashCommands.lua     # Static command dictionary
    └── Conditions.lua        # Macro condition definitions
```

---

## Compatibility

- **WoW Version**: Midnight (`## Interface: 120000`)
- **SavedVariables**: `MMO_GlobalDB` — stored at `WTF/Account/<NAME>/SavedVariables/MacroPlus.lua`
- **No external dependencies** — LibStub-free by design

---

## License

MIT

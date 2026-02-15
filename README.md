# Midnight Macro Overhaul (MMO)

A World of Warcraft addon for **Midnight (Interface: 120000)** that replaces the default Macro UI with a cross-character macro library, a modern IDE-style editor, and a searchable slash-command encyclopedia.

---

## Features

- **Cross-Character Library** — Browse and copy macros from all your alts, stored persistently across sessions via `SavedVariables`
- **IDE-Style Editor** — Multi-line editor with simulated syntax highlighting for slash commands and conditionals, plus a real-time character counter
- **Command Encyclopedia** — Searchable reference of every valid slash command in Midnight, with clickable insert buttons
- **Combat Safe** — All editing is automatically disabled during combat to prevent taint errors
- **Midnight Compatible** — Uses `C_Spell` APIs and targets Interface `120000`

---

## UI Layout

```
┌─────────────────────────────────────────────────────────┐
│  [Shared]          │  Macro Editor                       │
│  [□][□] macros     │  ┌─────────────────────────────┐   │
│                    │  │  multi-line EditBox          │   │
│  [Char 1]          │  │  (IDE editor + overlay)      │   │
│  [□][□] macros     │  │                              │   │
│                    │  └─────────────────────────────┘   │
│  [Char 2]          ├─────────────────────────────────── │
│  [□][□] macros     │  /commands                          │
│                    │  [/cast] [/use] [/target] ...       │
│  [+ more chars]    │  clickable → inserts into editor    │
└────────────────────┴────────────────────────────────────┘
```

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
5. Log in and type `/mmo` to open the Macro Hub

> Each deploy automatically backs up the previous version to `MacroPlus/backups/<timestamp>/` before deploying.

---

## Usage

| Command | Action |
|---------|--------|
| `/mmo` | Toggle the Macro Hub window |

- **Click a character** in the sidebar to browse their macros
- **Click a macro icon** to load it into the editor
- **Edit and save** — changes apply only to your current character
- **Copy to Current Char** — migrate any alt's macro to your active character
- **Click a /command button** in the encyclopedia to insert it at the cursor

---

## Project Structure

```
MacroPlus/
├── MacroPlus.toc
├── Core/
│   ├── Init.lua           # Addon entry point, namespace
│   ├── Database.lua       # MMO_GlobalDB accessors
│   └── CombatLock.lua     # Combat lockdown handling
├── Engine/
│   ├── Scraper.lua        # Macro data collection on login
│   └── Sync.lua           # Copy-to-character logic
├── UI/
│   ├── MainFrame.lua      # Main resizable window
│   ├── Sidebar.lua        # Character list by realm
│   ├── MacroGrid.lua      # Icon grid (ScrollFrame)
│   ├── SearchBar.lua      # Real-time macro filter
│   ├── Editor.lua         # IDE-style EditBox
│   └── CommandPanel.lua   # Slash command encyclopedia
└── Data/
    └── SlashCommands.lua  # Static command dictionary
```

---

## Compatibility

- **WoW Version**: Midnight (`## Interface: 120000`)
- **SavedVariables**: `MMO_GlobalDB` — stored at `WTF/Account/<NAME>/SavedVariables/MacroPlus.lua`

---

## License

MIT

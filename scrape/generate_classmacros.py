#!/usr/bin/env python3
"""Generate Data/ClassMacros.lua from recommended_macros.json + icy_veins_wow_macros.txt.

Includes full names, PvE/PvP split, Icy Veins URLs, and empty spec placeholders
so every spec with a URL appears as a tab in the UI.
"""

import json
import os
import re

CLASS_NAME_TO_ID = {
    "Death Knight": "DEATHKNIGHT",
    "Demon Hunter": "DEMONHUNTER",
    "Druid": "DRUID",
    "Evoker": "EVOKER",
    "Hunter": "HUNTER",
    "Mage": "MAGE",
    "Monk": "MONK",
    "Paladin": "PALADIN",
    "Priest": "PRIEST",
    "Rogue": "ROGUE",
    "Shaman": "SHAMAN",
    "Warlock": "WARLOCK",
    "Warrior": "WARRIOR",
}

CLASS_ORDER = [
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
]

def escape_lua_string(s):
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    s = s.replace("\n", "\\n")
    s = s.replace("\r", "")
    return s

def clean_desc(desc):
    """Clean description text, preserving full content for tooltips."""
    if not desc:
        return ""
    return desc.strip()

def is_valid_macro_content(content):
    """Check whether a macro content string is a usable WoW macro.

    A valid macro must have at least one slash command that is followed by
    a meaningful argument (spell name, command word, etc.), OR be a well-known
    standalone slash command like /petdismiss, /petfollow, /petmoveto,
    /startattack, /stopattack, /stopcasting, /cleartarget, /targetlasttarget,
    etc.

    Rejects:
    - Empty / whitespace-only content
    - Content that is just "/" with nothing after it
    - Section headers that were misidentified as macros (no slash commands)
    """
    if not content or not content.strip():
        return False

    stripped = content.strip()

    # Reject bare "/" or just whitespace around a single slash
    if stripped == "/":
        return False

    # Must contain at least one slash command (a "/" followed by a word)
    if not re.search(r'/[a-zA-Z]', stripped):
        return False

    return True

def parse_urls(txt_path):
    """Parse icy_veins_wow_macros.txt into { classID: { pve: { spec: url }, pvp: { spec: url } } }"""
    urls = {}
    current_mode = None

    with open(txt_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("PVE Links"):
                current_mode = "pve"
                continue
            if line.startswith("PVP Links"):
                current_mode = "pvp"
                continue
            if current_mode is None:
                continue

            # Format: "Class - Spec - URL"
            match = re.match(r'^(.+?)\s*-\s*(.+?)\s*-\s*(https?://.+)$', line)
            if not match:
                continue

            class_name = match.group(1).strip()
            spec = match.group(2).strip()
            url = match.group(3).strip()

            class_id = CLASS_NAME_TO_ID.get(class_name)
            if not class_id:
                continue

            if class_id not in urls:
                urls[class_id] = {"pve": {}, "pvp": {}}
            urls[class_id][current_mode][spec] = url

    return urls

def build_class_data(json_data, urls):
    """Build nested dict: classID -> mode -> spec -> [macros]
    Also ensures every spec from URLs exists (even if empty).
    Filters out macros with empty or invalid content."""
    result = {}
    skipped = 0

    # First, seed from URLs so every spec has at least an empty list
    for class_id, mode_urls in urls.items():
        if class_id not in result:
            result[class_id] = {"pve": {}, "pvp": {}}
        for mode in ("pve", "pvp"):
            for spec in mode_urls.get(mode, {}):
                if spec not in result[class_id][mode]:
                    result[class_id][mode][spec] = []

    # Then fill in macros from JSON
    for mode in ("pve", "pvp"):
        entries = json_data.get(mode, [])
        for entry in entries:
            class_name = entry.get("class", "")
            class_id = CLASS_NAME_TO_ID.get(class_name)
            if not class_id:
                continue

            spec = entry.get("spec", "General")
            macros = entry.get("macros", [])

            if class_id not in result:
                result[class_id] = {"pve": {}, "pvp": {}}

            if spec not in result[class_id][mode]:
                result[class_id][mode][spec] = []

            for m in macros:
                name = m.get("name", "Unnamed")
                body = m.get("content", "")
                desc = clean_desc(m.get("purpose", ""))

                # Filter out macros with empty or invalid content
                if not is_valid_macro_content(body):
                    skipped += 1
                    continue

                result[class_id][mode][spec].append({
                    "name": name,
                    "body": body,
                    "desc": desc,
                })

    if skipped:
        print(f"  Filtered out {skipped} macros with empty/invalid content")

    return result

def format_macro_entry(macro, indent):
    name = escape_lua_string(macro["name"])
    body = escape_lua_string(macro["body"])
    desc = escape_lua_string(macro["desc"])

    return (
        f'{indent}{{ name = "{name}", '
        f'body = "{body}", '
        f'icon = 134400, '
        f'desc = "{desc}" }}'
    )

def needs_brackets(key):
    if not key:
        return True
    if " " in key or "-" in key:
        return True
    if key[0].isdigit():
        return True
    return False

def format_key(key):
    if needs_brackets(key):
        return f'["{escape_lua_string(key)}"]'
    return key

def generate_lua(class_data, urls):
    lines = []
    lines.append('local _, MMO = ...')
    lines.append('')
    lines.append('-- Curated class/spec macro library sourced from Icy Veins (Midnight / 12.x)')
    lines.append('-- Structure: MMO.ClassMacros[CLASS].pve[Spec] and MMO.ClassMacros[CLASS].pvp[Spec]')
    lines.append('-- Each entry: { name = string, body = string, icon = number, desc = string }')
    lines.append('-- icon 134400 = INV_Misc_QuestionMark (default)')
    lines.append('')
    lines.append('MMO.ClassMacros = {')

    for class_id in CLASS_ORDER:
        if class_id not in class_data:
            continue

        data = class_data[class_id]
        lines.append(f'    {class_id} = {{')

        for mode in ("pve", "pvp"):
            specs = data.get(mode, {})
            if not specs:
                lines.append(f'        {mode} = {{}},')
                continue

            lines.append(f'        {mode} = {{')

            sorted_specs = sorted(specs.keys(), key=lambda s: (0 if s == "General" else 1, s))

            for spec in sorted_specs:
                macros = specs[spec]
                key = format_key(spec)

                if not macros:
                    lines.append(f'            {key} = {{}},')
                    continue

                lines.append(f'            {key} = {{')
                for macro in macros:
                    lines.append(format_macro_entry(macro, "                ") + ",")
                lines.append(f'            }},')

            lines.append(f'        }},')

        lines.append(f'    }},')

    lines.append('}')
    lines.append('')

    # Generate URL table
    lines.append('-- Icy Veins source URLs per class/spec/mode')
    lines.append('MMO.ClassMacroURLs = {')

    for class_id in CLASS_ORDER:
        if class_id not in urls:
            continue

        url_data = urls[class_id]
        lines.append(f'    {class_id} = {{')

        for mode in ("pve", "pvp"):
            mode_urls = url_data.get(mode, {})
            if not mode_urls:
                lines.append(f'        {mode} = {{}},')
                continue

            lines.append(f'        {mode} = {{')
            sorted_specs = sorted(mode_urls.keys(), key=lambda s: (0 if s == "General" else 1, s))
            for spec in sorted_specs:
                url = escape_lua_string(mode_urls[spec])
                key = format_key(spec)
                lines.append(f'            {key} = "{url}",')
            lines.append(f'        }},')

        lines.append(f'    }},')

    lines.append('}')
    lines.append('')

    return '\n'.join(lines)

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, "recommended_macros.json")
    txt_path = os.path.join(script_dir, "icy_veins_wow_macros.txt")
    lua_path = os.path.join(script_dir, "..", "Data", "ClassMacros.lua")

    with open(json_path, "r", encoding="utf-8") as f:
        json_data = json.load(f)

    urls = parse_urls(txt_path)
    class_data = build_class_data(json_data, urls)
    lua_content = generate_lua(class_data, urls)

    with open(lua_path, "w", encoding="utf-8") as f:
        f.write(lua_content)

    # Count macros and specs
    total_pve = 0
    total_pvp = 0
    total_specs = 0
    for cid, data in class_data.items():
        for spec, macros in data.get("pve", {}).items():
            total_pve += len(macros)
            total_specs += 1
        for spec, macros in data.get("pvp", {}).items():
            total_pvp += len(macros)
            total_specs += 1

    total_urls = sum(
        len(m_urls)
        for u in urls.values()
        for m_urls in u.values()
    )

    print(f"Generated {lua_path}")
    print(f"  PvE macros: {total_pve}")
    print(f"  PvP macros: {total_pvp}")
    print(f"  Total macros: {total_pve + total_pvp}")
    print(f"  Spec tabs: {total_specs}")
    print(f"  Icy Veins URLs: {total_urls}")
    print(f"  Classes: {len(class_data)}")

if __name__ == "__main__":
    main()

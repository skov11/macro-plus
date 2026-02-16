#!/usr/bin/env python3
"""
Scrape Icy Veins WoW macro pages and build a JSON file with
recommended macros per class/spec for PVE and PVP.

Each macro entry includes: name, content (the actual macro text), and purpose.

Uses polite rate limiting with random jitter, retries on failure,
and resume support to avoid getting blocked.
"""

import argparse
import hashlib
import json
import os
import random
import re
import time
import urllib.request
import sys

INPUT_FILE = "icy_veins_wow_macros.txt"
OUTPUT_FILE = "recommended_macros.json"
PROGRESS_FILE = "scrape_progress.json"
HASH_FILE = "scrape_hashes.json"

# Delay between requests: random between MIN and MAX seconds
DELAY_MIN = 4
DELAY_MAX = 8
# How many retries per page on failure
MAX_RETRIES = 3
# Backoff multiplier for retries (seconds)
RETRY_BACKOFF = 15
# Request timeout
REQUEST_TIMEOUT = 45

# Spec -> role mapping for PVP pages (PVE URLs contain the role)
SPEC_ROLES = {
    "Blood": "Tank",
    "Frost": "DPS",
    "Unholy": "DPS",
    "Havoc": "DPS",
    "Vengeance": "Tank",
    "Balance": "DPS",
    "Feral": "DPS",
    "Guardian": "Tank",
    "Restoration": "Healer",
    "Augmentation": "DPS",
    "Devastation": "DPS",
    "Preservation": "Healer",
    "Beast Mastery": "DPS",
    "Marksmanship": "DPS",
    "Survival": "DPS",
    "Arcane": "DPS",
    "Fire": "DPS",
    "Brewmaster": "Tank",
    "Mistweaver": "Healer",
    "Windwalker": "DPS",
    "Holy": "Healer",
    "Protection": "Tank",
    "Retribution": "DPS",
    "Discipline": "Healer",
    "Shadow": "DPS",
    "Assassination": "DPS",
    "Outlaw": "DPS",
    "Subtlety": "DPS",
    "Elemental": "DPS",
    "Enhancement": "DPS",
    "Affliction": "DPS",
    "Demonology": "DPS",
    "Destruction": "DPS",
    "Arms": "DPS",
    "Fury": "DPS",
}


def parse_input_file(path):
    """Parse the input file into PVE and PVP link lists."""
    pve_links = []
    pvp_links = []
    current_section = None

    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("PVE Links"):
                current_section = "pve"
                continue
            if line.startswith("PVP Links"):
                current_section = "pvp"
                continue

            match = re.match(r"^(.+?)\s*-\s*(.+?)\s*-\s*(https?://.+)$", line)
            if match:
                class_name = match.group(1).strip()
                spec_name = match.group(2).strip()
                url = match.group(3).strip()
                entry = {"class": class_name, "spec": spec_name, "url": url}

                if current_section == "pve":
                    url_lower = url.lower()
                    if "-tank-" in url_lower:
                        entry["role"] = "Tank"
                    elif "-healer-" in url_lower or "-healing-" in url_lower:
                        entry["role"] = "Healer"
                    else:
                        entry["role"] = "DPS"
                    pve_links.append(entry)
                elif current_section == "pvp":
                    entry["role"] = SPEC_ROLES.get(spec_name, "DPS")
                    pvp_links.append(entry)

    return pve_links, pvp_links


def polite_delay():
    """Sleep a random amount to be polite to the server."""
    delay = random.uniform(DELAY_MIN, DELAY_MAX)
    time.sleep(delay)


def fetch_page(url):
    """Fetch a page with retries and return cleaned text content."""
    for attempt in range(1, MAX_RETRIES + 1):
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/122.0.0.0 Safari/537.36"
                ),
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                html = resp.read().decode("utf-8", errors="replace")
        except Exception as e:
            if attempt < MAX_RETRIES:
                wait = RETRY_BACKOFF * attempt
                print(f"\n    retry {attempt}/{MAX_RETRIES} in {wait}s ({e})...",
                      end=" ", flush=True)
                time.sleep(wait)
                continue
            else:
                print(f"\n    FAILED after {MAX_RETRIES} attempts: {e}",
                      file=sys.stderr)
                return None

        # Find the page_content div
        start = html.find('class="page_content "')
        if start == -1:
            start = html.find('class="page_content"')
        if start == -1:
            print(f"\n    WARNING: No page_content found", file=sys.stderr)
            return None

        chunk = html[start : start + 50000]
        clean = re.sub(r"<[^>]+>", "\n", chunk)
        clean = re.sub(r"\n\s*\n", "\n", clean)
        return clean.strip()

    return None


def _extract_ability_name(code_block):
    """
    Extract an ability name from a code block using a waterfall approach:
    1. #showtooltip AbilityName (skip if it starts with /)
    2. Last /cast or /use line, stripping [conditions]
    3. /cancelaura lines
    4. Fall back to None
    """
    lines = code_block.strip().split("\n")

    # 1. Check #showtooltip
    for line in lines:
        if line.startswith("#showtooltip"):
            rest = line[len("#showtooltip"):].strip()
            if rest and not rest.startswith("/"):
                # Skip generic placeholders
                if rest.lower() in ("ability", "spell"):
                    return None
                return rest

    # 2. Check last /cast or /use line
    last_cast = None
    for line in lines:
        m = re.match(r"^/(?:cast|use)\s+", line)
        if m:
            ability = line[m.end():]
            # Strip [conditions] groups
            ability = re.sub(r"\[.*?\]\s*", "", ability).strip()
            # Strip leading ! (toggle prefix)
            ability = ability.lstrip("!")
            # Strip trailing ; and anything after (fallback spells)
            ability = ability.split(";")[0].strip()
            if ability and ability.lower() not in ("ability", "spell"):
                last_cast = ability

    if last_cast:
        return last_cast

    # 3. Check /cancelaura
    for line in lines:
        m = re.match(r"^/cancelaura\s+(.+)", line)
        if m:
            return m.group(1).strip()

    return None


def _extract_last_cast(code_block):
    """
    Extract the ability name from the last /cast or /use line in a code block.
    Used as a fallback when #showtooltip gives the same name across all blocks.
    """
    lines = code_block.strip().split("\n")
    last_cast = None
    for line in lines:
        m = re.match(r"^/(?:cast|use)\s+", line)
        if m:
            ability = line[m.end():]
            ability = re.sub(r"\[.*?\]\s*", "", ability).strip()
            ability = ability.lstrip("!")
            ability = ability.split(";")[0].strip()
            if ability and ability.lower() not in ("ability", "spell"):
                last_cast = ability
    return last_cast


def _merge_false_splits(code_blocks):
    """
    Merge code blocks that are false splits — a #showtooltip with no /commands
    followed by another block that has the actual commands.
    E.g., Monk Brewmaster has a duplicate #showtooltip line.
    """
    if len(code_blocks) <= 1:
        return code_blocks

    merged = []
    i = 0
    while i < len(code_blocks):
        block = code_blocks[i]
        block_lines = block.strip().split("\n")
        # Check if this block is ONLY #showtooltip lines (no / commands)
        has_commands = any(l.startswith("/") for l in block_lines)
        if not has_commands and i + 1 < len(code_blocks):
            # Merge with next block
            merged.append(block + "\n" + code_blocks[i + 1])
            i += 2
        else:
            merged.append(block)
            i += 1
    return merged


def _extract_macros_from_part(lines):
    """
    Given lines for a single macro section, extract name, content, and purpose.
    Returns a list of macro dicts (may be empty). When multiple code blocks
    exist, each becomes a separate macro entry.
    """
    if not lines:
        return []

    macro_name = lines[0]

    # Skip section headers
    skip_patterns = ["generic macros", "specific macros", "macros for"]
    name_lower = macro_name.lower()
    if any(name_lower.startswith(p) for p in skip_patterns):
        return []

    # Walk through lines collecting code blocks and description
    code_blocks = []      # list of code block strings
    current_code = []     # lines in the current code block
    description_lines = []
    in_code = False

    for line in lines[1:]:
        is_code_line = (
            line.startswith("#showtooltip")
            or line.startswith("/")
            or line.startswith("#show ")
        )
        is_block_start = (
            line.startswith("#showtooltip")
            or line.startswith("#show ")
        )

        if is_code_line:
            if is_block_start and current_code:
                # #showtooltip always starts a new code block
                code_blocks.append("\n".join(current_code))
                current_code = []
            elif not in_code and current_code:
                code_blocks.append("\n".join(current_code))
                current_code = []
            in_code = True
            current_code.append(line)
        else:
            if in_code:
                # End of a code block
                code_blocks.append("\n".join(current_code))
                current_code = []
                in_code = False
            # Stop collecting description at sub-section numbering
            if re.match(r"^\d+\.\d+", line):
                break
            description_lines.append(line)

    # Don't forget the last code block
    if current_code:
        code_blocks.append("\n".join(current_code))

    # Build shared purpose text
    purpose = " ".join(description_lines).strip()
    purpose = re.sub(r"\s+", " ", purpose)
    purpose = purpose.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    # No truncation — full descriptions stored for tooltip display

    # Clean name
    macro_name = macro_name.replace("&amp;", "&")

    if not macro_name:
        return []

    # Merge false splits before deciding how many macros we have
    code_blocks = _merge_false_splits(code_blocks)

    # Single code block (or none) — return one macro as before
    if len(code_blocks) <= 1:
        content = code_blocks[0] if code_blocks else ""
        return [{"name": macro_name, "content": content, "purpose": purpose}]

    # Multiple code blocks — split into separate macros
    # First pass: extract raw ability names to check for duplicates
    raw_abilities = [_extract_ability_name(block) for block in code_blocks]

    # If all abilities are the same (e.g., all "Pillar of Frost" from tooltip),
    # try extracting from the last /cast line instead for differentiation
    unique_abilities = set(a for a in raw_abilities if a)
    if len(unique_abilities) == 1:
        for i, block in enumerate(code_blocks):
            last_cast = _extract_last_cast(block)
            if last_cast and last_cast != raw_abilities[i]:
                raw_abilities[i] = last_cast

    macros = []
    seen_names = {}  # track sub-names for dedup
    for block, ability in zip(code_blocks, raw_abilities):
        if ability:
            sub_name = f"{macro_name} \u2014 {ability}"
        else:
            sub_name = None  # will assign Variant N below

        # Deduplicate names
        if sub_name:
            count = seen_names.get(sub_name, 0) + 1
            seen_names[sub_name] = count
            if count > 1:
                sub_name = f"{sub_name} ({count})"
        else:
            # Fallback: Variant N
            variant_n = sum(1 for n in seen_names if n.startswith(f"{macro_name} \u2014 Variant")) + 1
            sub_name = f"{macro_name} \u2014 Variant {variant_n}"
            seen_names[sub_name] = 1

        macros.append({"name": sub_name, "content": block, "purpose": purpose})

    return macros


def _extract_macros_from_parts(parts):
    """Given split parts (first is preamble, rest are sections), extract macros."""
    macros = []
    for part in parts[1:]:
        lines = [l.strip() for l in part.strip().split("\n") if l.strip()]
        macros.extend(_extract_macros_from_part(lines))
    return macros


def parse_macros_pve(text):
    """
    Parse PVE macro page content.
    Handles 3-level (1.1.1.) and 2-level (1.1.) numbering.
    Some pages put addons first (section 1) and macros in section 2+,
    so we use flexible cutoff patterns.
    """
    if not text:
        return []

    # Cut off at the Addons section or Changelog.
    # Match any top-level section number followed by "Addons" (e.g. "2.\nAddons" or "3.\nAddons")
    for cutoff_pattern in [
        r"\n\d+\.\s*\nAddons for ",        # "3.\nAddons for Havoc Demon Hunters"
        r"\n\d+\.\s*\nAddons\n",            # "2.\nAddons\n"
        r"\nChangelog\n",
    ]:
        cut = re.search(cutoff_pattern, text)
        if cut:
            text = text[: cut.start()]
            break

    # Try 3-level numbering first (most common): 1.1.1., 1.1.2., etc.
    parts_3 = re.split(r"\n\d+\.\d+\.\d+\.\s*\n", text)
    macros_3 = _extract_macros_from_parts(parts_3)
    # Only use 3-level results if at least one has actual macro code
    macros_3_with_code = [m for m in macros_3 if m.get("content")]
    if macros_3_with_code:
        return macros_3_with_code

    # Fallback to 2-level numbering: 1.1., 1.2., 2.1., etc.
    parts_2 = re.split(r"\n\d+\.\d+\.\s*\n", text)
    macros_2 = _extract_macros_from_parts(parts_2)
    macros_2_with_code = [m for m in macros_2 if m.get("content")]
    if macros_2_with_code:
        return macros_2_with_code

    return macros_2


def parse_macros_pvp(text):
    """
    Parse PVP macro page content.
    Format: simple numbered list (1., 2., 3.).
    """
    macros = []
    if not text:
        return macros

    # Cut off at changelog
    cut = re.search(r"\nChangelog\n", text)
    if cut:
        text = text[: cut.start()]

    # Split by top-level numbers: "\nN.\n"
    parts = re.split(r"\n(\d+)\.\s*\n", text)

    # parts: [preamble, num, content, num, content, ...]
    i = 1
    while i < len(parts) - 1:
        content = parts[i + 1]
        i += 2

        lines = [l.strip() for l in content.strip().split("\n") if l.strip()]
        if not lines:
            continue

        # Skip non-macro sections
        if lines[0].lower() in ("changelog", "addons", "about the author"):
            continue

        macros.extend(_extract_macros_from_part(lines))

    return macros


def make_key(section, class_name, spec_name):
    """Create a unique key for progress tracking."""
    return f"{section}|{class_name}|{spec_name}"


def load_progress():
    """Load progress file if it exists (for resume support)."""
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r") as f:
            return json.load(f)
    return {}


def save_progress(progress):
    """Save progress to disk."""
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f)


def parse_args():
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Scrape Icy Veins WoW macro pages into recommended_macros.json"
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Skip pages whose content hash hasn't changed; show diff",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-scrape everything but still show diff against existing output",
    )
    return parser.parse_args()


# --- Hashing helpers ---

def compute_hash(text):
    """SHA-256 hex digest of page text."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_hashes():
    """Load page content hashes from disk."""
    if os.path.exists(HASH_FILE):
        with open(HASH_FILE, "r") as f:
            return json.load(f)
    return {}


def save_hashes(hashes):
    """Save page content hashes to disk."""
    with open(HASH_FILE, "w") as f:
        json.dump(hashes, f, indent=2)


# --- Diff reporting ---

def _find_existing_macros(existing_data, class_name, spec_name, section):
    """Look up a class/spec's macros in existing JSON data."""
    if not existing_data:
        return []
    for entry in existing_data.get(section, []):
        if entry["class"] == class_name and entry["spec"] == spec_name:
            return entry.get("macros", [])
    return []


def _print_diff_report(old_data, new_data):
    """Compare old and new macro data and print a human-readable diff."""
    old_map = {}  # (section, class, spec, name) -> content
    new_map = {}

    for section in ("pve", "pvp"):
        for entry in old_data.get(section, []):
            for m in entry.get("macros", []):
                key = (section, entry["class"], entry["spec"], m["name"])
                old_map[key] = m.get("content", "")
        for entry in new_data.get(section, []):
            for m in entry.get("macros", []):
                key = (section, entry["class"], entry["spec"], m["name"])
                new_map[key] = m.get("content", "")

    added = sorted(k for k in new_map if k not in old_map)
    removed = sorted(k for k in old_map if k not in new_map)
    changed = sorted(
        k for k in new_map if k in old_map and new_map[k] != old_map[k]
    )

    if not added and not removed and not changed:
        print("\n  No changes detected vs. existing output.")
        return

    print(f"\n  === Diff Report ===")
    if added:
        print(f"  + {len(added)} added:")
        for k in added:
            print(f"      + {k[0].upper()} {k[1]} {k[2]}: {k[3]}")
    if changed:
        print(f"  ~ {len(changed)} changed:")
        for k in changed:
            print(f"      ~ {k[0].upper()} {k[1]} {k[2]}: {k[3]}")
    if removed:
        print(f"  - {len(removed)} removed:")
        for k in removed:
            print(f"      - {k[0].upper()} {k[1]} {k[2]}: {k[3]}")


def _print_summary(result):
    """Print final summary statistics."""
    total_pve = sum(len(e["macros"]) for e in result["pve"])
    total_pvp = sum(len(e["macros"]) for e in result["pvp"])
    with_code = sum(
        1 for section in ["pve", "pvp"]
        for e in result[section]
        for m in e["macros"]
        if m.get("content")
    )
    without_code = sum(
        1 for section in ["pve", "pvp"]
        for e in result[section]
        for m in e["macros"]
        if not m.get("content")
    )
    zeros = [
        f"{s.upper()}: {e['class']} - {e['spec']}"
        for s in ["pve", "pvp"]
        for e in result[s]
        if len(e["macros"]) == 0
    ]

    print(f"\n=== Done ===")
    print(f"  PVE: {len(result['pve'])} specs, {total_pve} macros")
    print(f"  PVP: {len(result['pvp'])} specs, {total_pvp} macros")
    print(f"  Total: {total_pve + total_pvp} macros ({with_code} with code, {without_code} without)")
    if zeros:
        print(f"  WARNING - 0 macros: {', '.join(zeros)}")
    else:
        print(f"  All entries have macros!")
    print(f"  Written to {OUTPUT_FILE}")


def main():
    args = parse_args()
    use_hashing = args.update or args.force
    show_diff = args.update or args.force

    print("Parsing input file...")
    pve_links, pvp_links = parse_input_file(INPUT_FILE)
    print(f"  Found {len(pve_links)} PVE links, {len(pvp_links)} PVP links")

    # Load existing output for diff comparison and --update reuse
    existing_data = None
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r") as f:
            existing_data = json.load(f)

    # Load progress for resume support
    progress = load_progress()
    if progress:
        done = sum(1 for v in progress.values() if v.get("macros") is not None)
        print(f"  Resuming: {done}/{len(pve_links) + len(pvp_links)} already scraped")

    # Load content hashes for --update mode
    hashes = load_hashes() if use_hashing else {}

    all_pages = []
    for entry in pve_links:
        all_pages.append({**entry, "section": "pve", "parser": "pve"})
    for entry in pvp_links:
        all_pages.append({**entry, "section": "pvp", "parser": "pvp"})

    total = len(all_pages)
    skipped_unchanged = 0

    for i, page in enumerate(all_pages):
        key = make_key(page["section"], page["class"], page["spec"])
        label = f"[{i+1}/{total}] {page['section'].upper()} {page['class']} - {page['spec']}"

        # Skip if already done (resume support)
        if key in progress and progress[key].get("macros") is not None:
            count = len(progress[key]["macros"])
            print(f"  {label}... cached ({count} macros)")
            continue

        print(f"  {label}...", end=" ", flush=True)

        text = fetch_page(page["url"])

        # --update mode: check hash, skip if unchanged
        if args.update and text:
            page_hash = compute_hash(text)
            if hashes.get(key) == page_hash and existing_data:
                # Reuse macros from existing output
                reused = _find_existing_macros(
                    existing_data, page["class"], page["spec"], page["section"]
                )
                print(f"unchanged ({len(reused)} macros)")
                progress[key] = {
                    "class": page["class"],
                    "spec": page["spec"],
                    "role": page["role"],
                    "section": page["section"],
                    "macros": reused,
                }
                save_progress(progress)
                skipped_unchanged += 1
                # Still need polite delay for the fetch we already did
                if i < total - 1:
                    polite_delay()
                continue
            # Hash changed or new page — update stored hash
            hashes[key] = page_hash

        if page["parser"] == "pve":
            macros = parse_macros_pve(text)
        else:
            macros = parse_macros_pvp(text)

        print(f"found {len(macros)} macros")
        for m in macros:
            has_code = "yes" if m["content"] else "NO CODE"
            print(f"    - {m['name']} [{has_code}]")

        # Store hash for --force mode too
        if args.force and text:
            hashes[key] = compute_hash(text)

        progress[key] = {
            "class": page["class"],
            "spec": page["spec"],
            "role": page["role"],
            "section": page["section"],
            "macros": macros,
        }

        # Save progress after each page
        save_progress(progress)

        # Polite delay before next request
        if i < total - 1:
            polite_delay()

    if skipped_unchanged:
        print(f"\n  Skipped {skipped_unchanged} unchanged pages")

    # Build final output
    result = {"pve": [], "pvp": []}
    for page in all_pages:
        key = make_key(page["section"], page["class"], page["spec"])
        entry = progress[key]
        result[entry["section"]].append({
            "class": entry["class"],
            "spec": entry["spec"],
            "role": entry["role"],
            "macros": entry["macros"],
        })

    # Show diff if requested
    if show_diff and existing_data:
        _print_diff_report(existing_data, result)

    with open(OUTPUT_FILE, "w") as f:
        json.dump(result, f, indent=2)

    # Save hashes
    if use_hashing:
        save_hashes(hashes)

    # Cleanup progress file on success
    if os.path.exists(PROGRESS_FILE):
        os.remove(PROGRESS_FILE)

    _print_summary(result)


if __name__ == "__main__":
    main()

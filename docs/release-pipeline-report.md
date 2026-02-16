# Research Report: Automating WoW Addon Packaging and CurseForge Release for MacroPlus

**Date:** 2026-02-15
**Subject:** Complete CI/CD pipeline for packaging, uploading, and distributing a WoW addon
**Addon:** MacroPlus (Interface: 120000 / WoW Midnight)

---

## Executive Summary

Automating the release of a WoW addon to CurseForge (and optionally Wago Addons) involves three main components: (1) packaging the addon into a properly structured zip file, (2) authenticating with the CurseForge Upload API using an API token, and (3) uploading the zip with metadata describing the game version, release type, and changelog.

The WoW addon community has a mature, well-established toolchain for this. The **BigWigsMods/packager** is the de facto standard, used by the vast majority of WoW addon authors. It is available both as a standalone bash script (`release.sh`) and as a GitHub Action (`BigWigsMods/packager@v2`). It handles packaging, changelog generation, version detection from git tags, and uploading to CurseForge, Wago Addons, WoWInterface, and GitHub Releases -- all in one step.

For MacroPlus specifically, the recommended approach is:

1. Add `X-Curse-Project-ID` and `X-Wago-ID` fields to `MacroPlus.toc`
2. Create a `.pkgmeta` file to exclude development files from the release zip
3. Set up a GitHub Actions workflow that triggers on git tag pushes
4. Store API tokens as GitHub repository secrets

This report provides complete, copy-pasteable configurations for all of these steps, plus a local bash script alternative for manual releases.

---

## Key Research Questions Addressed

1. Does CurseForge have an official upload API, and how does it work?
2. What authentication is required and how do you obtain tokens?
3. What metadata is required when uploading (game versions, release type, changelog)?
4. How does the BigWigsMods/packager work and how do you configure it?
5. What does a complete GitHub Actions release workflow look like?
6. How do you find your CurseForge project ID and game version IDs?
7. What is the `.pkgmeta` file format and what should MacroPlus's look like?
8. Can you also upload to Wago Addons with the same pipeline?
9. What does a local (non-CI) release script look like?
10. What are the common pitfalls and gotchas?

---

## Detailed Findings

### 1. CurseForge Upload API

CurseForge provides an official Upload API for addon/mod authors. This is separate from the "CurseForge for Studios API" (which is for game studios integrating UGC). The Upload API is specifically for project authors to programmatically upload new file versions.

#### Base URL

For WoW addons, the base URL is:

```
https://wow.curseforge.com
```

The upload endpoint is:

```
POST https://wow.curseforge.com/api/projects/{projectId}/upload-file
```

Where `{projectId}` is your numeric CurseForge project ID.

#### Authentication

Authentication uses an API token passed via the `X-Api-Token` HTTP header (or as a `token` query parameter, though the header is preferred).

**How to generate a token:**

1. Log in to CurseForge at https://www.curseforge.com
2. Navigate to https://www.curseforge.com/account/api-tokens
3. Enter a descriptive name (e.g., "GitHub Actions Release") and generate the token
4. Copy the token immediately -- it is shown only once

#### Request Format

The upload is a `multipart/form-data` POST with two fields:

| Field | Type | Description |
|-------|------|-------------|
| `metadata` | JSON string | Release metadata (see below) |
| `file` | File | The addon zip file |

#### Metadata Schema

```json
{
  "changelog": "String describing changes (can be multi-line)",
  "changelogType": "text",
  "displayName": "MacroPlus v1.0.0",
  "gameVersions": [12345],
  "releaseType": "release",
  "relations": {
    "projects": []
  }
}
```

| Field | Required | Values | Notes |
|-------|----------|--------|-------|
| `changelog` | Yes | Any string | Release notes |
| `changelogType` | No | `text`, `html`, `markdown` | Defaults to `text` |
| `displayName` | No | Any string | Friendly name shown on CurseForge; defaults to filename |
| `gameVersions` | Yes | Array of integers | Numeric version IDs from the game versions API |
| `releaseType` | Yes | `release`, `beta`, `alpha` | Stability level |
| `parentFileID` | No | Integer | For uploading additional files to an existing version |
| `relations` | No | Object | Dependencies (see below) |

#### Relations (Dependencies)

```json
{
  "relations": {
    "projects": [
      {
        "slug": "some-library",
        "type": "requiredDependency"
      }
    ]
  }
}
```

Relation types: `embeddedLibrary`, `incompatible`, `optionalDependency`, `requiredDependency`, `tool`

MacroPlus has no external dependencies, so this field can be omitted.

#### Game Version IDs

Game version IDs are numeric and must be fetched from the API:

```
GET https://wow.curseforge.com/api/game/versions?token={YOUR_TOKEN}
```

This returns an array like:

```json
[
  { "id": 12345, "gameVersionTypeID": 517, "name": "12.0.0", "slug": "12-0-0" },
  ...
]
```

For WoW Retail, the `gameVersionTypeID` is `517`. You need to find the entry matching your Interface version (120000 = WoW 12.0.0 Midnight).

**Important:** The BigWigsMods packager handles this automatically by reading the `## Interface:` line from your `.toc` file and mapping it to the correct game version IDs. You do not need to manually look these up if you use the packager.

#### Response

On success, the API returns:

```json
{ "id": 67890 }
```

Where `id` is the new file's ID on CurseForge.

#### Rate Limits

CurseForge does not publicly document specific rate limits for the Upload API. In practice, addon releases are infrequent enough that rate limits are not a concern. The BigWigsMods packager has been used by hundreds of addon authors without rate limit issues.

---

### 2. BigWigsMods/packager (The Standard Tool)

The BigWigsMods packager (`https://github.com/BigWigsMods/packager`) is the de facto standard for WoW addon packaging. It is a comprehensive bash script (`release.sh`) that handles the entire release pipeline.

#### What It Does

1. Creates a clean `.release/` directory
2. Copies addon files from your git checkout (respecting `.pkgmeta` ignore rules)
3. Checks out external library repositories (if configured)
4. Performs string replacements (`@project-version@`, etc.)
5. Processes build-type keywords (`--@alpha@`, `--@debug@`, etc.)
6. Generates a changelog from git history (commits since previous tag)
7. Zips the result into a distributable addon package
8. Uploads to CurseForge, Wago Addons, WoWInterface, and/or GitHub Releases

#### How It Identifies Versions

The packager assumes you use **git tags** for version numbers. When you push a tag like `v1.0.0` or `1.0.0`:

- The tag name becomes the version
- The changelog is generated from commits between this tag and the previous tag
- The release type is inferred: tags containing `alpha` or `beta` are marked accordingly; otherwise it is `release`

#### How It Knows Where to Upload

The packager reads project IDs from your `.toc` file:

```
## X-Curse-Project-ID: 123456
## X-Wago-ID: abcdef12
## X-WoWI-ID: 78901
```

Alternatively, you can pass them as command-line flags: `-p` (CurseForge), `-a` (Wago), `-w` (WoWInterface).

#### Environment Variables for Upload

| Variable | Platform | How to Obtain |
|----------|----------|---------------|
| `CF_API_KEY` | CurseForge | https://www.curseforge.com/account/api-tokens |
| `WAGO_API_TOKEN` | Wago Addons | https://addons.wago.io/account/apikeys |
| `WOWI_API_TOKEN` | WoWInterface | WoWInterface account settings |
| `GITHUB_OAUTH` | GitHub Releases | Automatically provided as `GITHUB_TOKEN` in Actions |

#### Command-Line Options

Key flags for the `release.sh` script:

| Flag | Description |
|------|-------------|
| `-d` | Skip uploading (dry run / package only) |
| `-c` | Skip file copying |
| `-e` | Skip external checkout |
| `-l` | Skip localization |
| `-z` | Skip zip creation |
| `-s` | Create nolib package |
| `-p ID` | Set CurseForge project ID |
| `-w ID` | Set WoWInterface addon ID |
| `-a ID` | Set Wago project ID |
| `-g TYPE` | Set game type (retail, classic, wrath, cata) |
| `-n TMPL` | Set output filename template |
| `-t DIR` | Set top-level directory |
| `-r DIR` | Set release output directory |

#### String Replacements

The packager replaces these tokens in your source files during packaging:

| Token | Replacement |
|-------|-------------|
| `@project-version@` | The version from the git tag |
| `@project-revision@` | Number of commits |
| `@project-hash@` | Full commit hash |
| `@project-abbreviated-hash@` | Short commit hash |
| `@project-author@` | Last commit author |
| `@project-date-iso@` | Last commit date (ISO) |
| `@project-timestamp@` | Last commit Unix timestamp |

This means you can put `@project-version@` in your `.toc` file and it will be automatically updated:

```
## Version: @project-version@
```

#### Build-Type Keywords

You can have code that only runs in development (not in packaged releases):

```lua
--@debug@
print("DEBUG: This line is stripped from release builds")
--@end-debug@
```

Or code only included in alpha builds:

```lua
--@alpha@
print("ALPHA: experimental feature")
--@end-alpha@
```

---

### 3. The .pkgmeta File

The `.pkgmeta` file (placed in the repo root) tells the packager what to include/exclude and how to structure the package.

#### Complete .pkgmeta for MacroPlus

```yaml
package-as: MacroPlus

ignore:
  - .github
  - .gitignore
  - .gitattributes
  - .env
  - .env-example
  - .luacheckrc
  - .pkgmeta
  - CLAUDE.md
  - README.md
  - LICENSE
  - deploy.sh
  - docs
  - scrape
  - screenshots
  - "*.md"
```

**Explanation of directives:**

- `package-as: MacroPlus` -- The root folder inside the zip will be named `MacroPlus`, and the zip will be named `MacroPlus-{version}.zip`. This must match your addon folder name.

- `ignore:` -- Files and directories to exclude from the package. Files starting with `.` (like `.pkgmeta`, `.git`) are automatically excluded, but it does not hurt to be explicit. The packager uses glob patterns.

**Notes:**
- YAML files must use **spaces** for indentation, never tabs
- On Windows, create the file as `.pkgmeta.` (trailing dot) and Windows will strip it, leaving `.pkgmeta`
- Files beginning with `.` are automatically ignored, but listing them explicitly is a good safety practice

#### Other .pkgmeta Directives (Not Needed for MacroPlus)

Since MacroPlus has no external library dependencies, these are documented for reference only:

- `externals:` -- Checkout external library repos into the package
- `move-folders:` -- Relocate subdirectories in the final package
- `manual-changelog:` -- Use a CHANGELOG.md instead of auto-generated git log
- `enable-nolib-creation: yes` -- Create a second zip without libraries
- `required-dependencies:` / `optional-dependencies:` -- Declare CurseForge project dependencies
- `tools-used:` -- List tools for CurseForge Author Rewards
- `plain-copy:` -- Files that should not have string replacements applied

---

### 4. CurseForge Project Setup

#### Creating a Project

1. Go to https://www.curseforge.com/project/create
2. Select "World of Warcraft" as the game
3. Select "Addons" as the project type
4. Fill in:
   - **Project Name:** MacroPlus
   - **URL Slug:** macro-plus (auto-generated, can be customized)
   - **Summary:** Cross-character macro library with IDE-style editor and slash-command encyclopedia
   - **Description:** (full description, supports markdown)
   - **Categories:** select relevant ones (e.g., "Action Bars", "Miscellaneous")
   - **License:** choose your license
5. Submit for approval (CurseForge reviews new projects)

#### Finding Your Project ID

After your project is approved:

1. Go to your project page on CurseForge
2. Look at the right sidebar under "About Project"
3. The **Project ID** is a numeric value displayed there (e.g., `1234567`)

Alternatively, it appears in the URL when you go to your project management page.

#### Adding the Project ID to Your TOC

Add these lines to `MacroPlus.toc`:

```
## X-Curse-Project-ID: YOUR_PROJECT_ID_HERE
## X-Wago-ID: YOUR_WAGO_ID_HERE
```

---

### 5. GitHub Actions Workflow

This is the recommended approach for automated releases.

#### Complete `.github/workflows/release.yml`

```yaml
name: Package and Release

on:
  push:
    tags:
      - "v*"
      - "[0-9]*"

jobs:
  release:
    runs-on: ubuntu-latest

    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - name: Clone project
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Package and release
        uses: BigWigsMods/packager@v2
```

That is the complete workflow. The BigWigsMods packager action handles everything else.

#### What This Workflow Does

1. **Triggers** when you push a tag matching `v*` (e.g., `v1.0.0`, `v0.2.0-beta`) or a bare version number (e.g., `1.0.0`)
2. **Clones** the full repository with `fetch-depth: 0` (needed for changelog generation from git history)
3. **Runs** the BigWigsMods packager, which:
   - Reads `MacroPlus.toc` for interface version, project IDs, and version
   - Reads `.pkgmeta` for ignore rules and packaging configuration
   - Replaces `@project-version@` tokens with the tag name
   - Generates a changelog from git commits since the last tag
   - Creates `MacroPlus-{version}.zip`
   - Uploads to CurseForge (if `CF_API_KEY` is set and `X-Curse-Project-ID` is in TOC)
   - Uploads to Wago Addons (if `WAGO_API_TOKEN` is set and `X-Wago-ID` is in TOC)
   - Creates a GitHub Release with the zip attached (if `GITHUB_OAUTH` is set)

#### Required GitHub Secrets

Go to your GitHub repository > Settings > Secrets and variables > Actions > New repository secret:

| Secret Name | Value | Required? |
|-------------|-------|-----------|
| `CF_API_KEY` | Your CurseForge API token | Yes (for CurseForge upload) |
| `WAGO_API_TOKEN` | Your Wago Addons API token | Optional (for Wago upload) |

**Note:** `GITHUB_TOKEN` is automatically provided by GitHub Actions -- you do NOT need to create it. However, you may need to configure its permissions:

1. Go to repository Settings > Actions > General
2. Under "Workflow permissions", select "Read and write permissions"
3. This allows the packager to create GitHub Releases

#### How to Create a Release

```bash
# Tag the release
git tag -a v1.0.0 -m "Release v1.0.0"

# Push the tag to trigger the workflow
git push origin v1.0.0
```

The `-a` flag creates an **annotated tag**, which is the recommended type. The packager works with both annotated and lightweight tags, but annotated tags are best practice.

#### Expanded Workflow with Manual Trigger

If you also want the ability to trigger releases manually from the GitHub UI:

```yaml
name: Package and Release

on:
  push:
    tags:
      - "v*"
      - "[0-9]*"

  # Allow manual trigger from Actions tab
  workflow_dispatch:
    inputs:
      release_type:
        description: "Release type"
        required: true
        default: "release"
        type: choice
        options:
          - release
          - beta
          - alpha

jobs:
  release:
    runs-on: ubuntu-latest

    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - name: Clone project
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Package and release
        uses: BigWigsMods/packager@v2
```

---

### 6. TOC File Updates for MacroPlus

Your current `MacroPlus.toc` needs these additions for the automated pipeline:

```
## Interface: 120000
## Title: MacroPlus
## Notes: Cross-character macro library with IDE-style editor and slash-command encyclopedia
## Author: Big-Bro-Bot
## Version: @project-version@
## SavedVariables: MMO_GlobalDB
## X-Curse-Project-ID: YOUR_CURSEFORGE_PROJECT_ID
## X-Wago-ID: YOUR_WAGO_PROJECT_ID
```

**Key changes:**

1. `## Version: @project-version@` -- The packager replaces this token with the git tag version. During local development, the literal string `@project-version@` will appear, which is fine. In packaged releases, it becomes `v1.0.0` (or whatever your tag is). If you prefer to keep a hardcoded version for local development, you can keep `0.1.0` and let the packager overwrite it only in releases.

2. `## X-Curse-Project-ID:` -- Your numeric CurseForge project ID (obtained after creating the project on CurseForge).

3. `## X-Wago-ID:` -- Your Wago Addons project ID (obtained after creating the project on Wago).

---

### 7. Wago Addons Integration

Wago Addons (https://addons.wago.io) is the addon platform behind the WoWUp addon manager. It has its own upload API and is fully supported by the BigWigsMods packager.

#### Wago Upload API

**Endpoint:**
```
POST https://addons.wago.io/api/projects/{projectId}/version
```

**Authentication:**
```
Authorization: Bearer YOUR_API_TOKEN
```

**Request format:** `multipart/form-data` with `metadata` (JSON string) and `file` fields.

**Metadata schema:**
```json
{
  "label": "1.0.0",
  "stability": "stable",
  "changelog": "## Changes\n- Feature X\n- Bug fix Y",
  "supported_retail_patch": "12.0.0"
}
```

| Field | Values |
|-------|--------|
| `stability` | `stable`, `beta`, `alpha` |
| `supported_retail_patch` | e.g., `12.0.0` |
| `supported_classic_patch` | e.g., `1.15.5` |
| `supported_wotlk_patch` | e.g., `3.4.3` |
| `supported_bc_patch` | e.g., `2.5.4` |

At least one `supported_*_patch` field is required.

**Available patch versions can be queried:**
```
GET https://addons.wago.io/api/data/game
```

#### Wago Setup

1. Create an account at https://addons.wago.io
2. Submit your addon project
3. Get your project ID from the developer dashboard
4. Generate an API key at https://addons.wago.io/account/apikeys
5. Add the key as `WAGO_API_TOKEN` in your GitHub secrets
6. Add `## X-Wago-ID: your_project_id` to your `.toc` file

**The BigWigsMods packager handles all Wago uploads automatically when these are configured.**

---

### 8. Local Script Alternative

If you want to package and upload manually without CI/CD, here is a complete bash script.

#### `release-local.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# MacroPlus Local Release Script
# Usage: ./release-local.sh [version] [release_type]
# Example: ./release-local.sh 1.0.0 release
# Example: ./release-local.sh 0.9.0 beta
# ============================================================

ADDON_NAME="MacroPlus"
VERSION="${1:?Usage: $0 <version> [release|beta|alpha]}"
RELEASE_TYPE="${2:-release}"

# --- Configuration ---
# Set these or export them as environment variables before running
CF_API_KEY="${CF_API_KEY:?Set CF_API_KEY environment variable}"
CF_PROJECT_ID="${CF_PROJECT_ID:?Set CF_PROJECT_ID environment variable}"

# Optional: Wago
WAGO_API_TOKEN="${WAGO_API_TOKEN:-}"
WAGO_PROJECT_ID="${WAGO_PROJECT_ID:-}"

# --- Build the zip ---
RELEASE_DIR=".release"
PACKAGE_DIR="${RELEASE_DIR}/${ADDON_NAME}"
ZIP_FILE="${RELEASE_DIR}/${ADDON_NAME}-${VERSION}.zip"

echo "==> Cleaning release directory..."
rm -rf "${RELEASE_DIR}"
mkdir -p "${PACKAGE_DIR}"

echo "==> Copying addon files..."
# Copy all addon files, excluding dev/build files
rsync -a \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.gitignore' \
  --exclude='.gitattributes' \
  --exclude='.env' \
  --exclude='.env-example' \
  --exclude='.pkgmeta' \
  --exclude='.luacheckrc' \
  --exclude='.release' \
  --exclude='CLAUDE.md' \
  --exclude='README.md' \
  --exclude='LICENSE' \
  --exclude='deploy.sh' \
  --exclude='release-local.sh' \
  --exclude='docs/' \
  --exclude='scrape/' \
  --exclude='screenshots/' \
  --exclude='.claude/' \
  --exclude='*.md' \
  ./ "${PACKAGE_DIR}/"

# Update version in TOC if using @project-version@ token
if grep -q '@project-version@' "${PACKAGE_DIR}/${ADDON_NAME}.toc" 2>/dev/null; then
  sed -i "s/@project-version@/${VERSION}/g" "${PACKAGE_DIR}/${ADDON_NAME}.toc"
fi

echo "==> Creating zip..."
cd "${RELEASE_DIR}"
zip -r "../${ZIP_FILE}" "${ADDON_NAME}/"
cd ..

echo "==> Created: ${ZIP_FILE}"

# --- Generate changelog from git ---
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [ -n "${PREV_TAG}" ]; then
  CHANGELOG=$(git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" --no-merges)
else
  CHANGELOG=$(git log --pretty=format:"- %s" --no-merges -20)
fi

echo ""
echo "==> Changelog:"
echo "${CHANGELOG}"
echo ""

# --- Fetch game version IDs from CurseForge ---
echo "==> Fetching CurseForge game versions..."
GAME_VERSIONS_JSON=$(curl -s \
  -H "X-Api-Token: ${CF_API_KEY}" \
  "https://wow.curseforge.com/api/game/versions")

# Find version IDs matching WoW 12.0.x (Midnight)
# You may need to adjust the grep pattern for your specific version
GAME_VERSION_IDS=$(echo "${GAME_VERSIONS_JSON}" | \
  jq '[.[] | select(.name | startswith("12.0")) | .id]')

if [ "${GAME_VERSION_IDS}" = "[]" ] || [ -z "${GAME_VERSION_IDS}" ]; then
  echo "WARNING: Could not auto-detect game version IDs."
  echo "Please check available versions and set manually."
  echo "Available versions matching '12':"
  echo "${GAME_VERSIONS_JSON}" | jq '.[] | select(.name | contains("12")) | {id, name}'
  exit 1
fi

echo "==> Game version IDs: ${GAME_VERSION_IDS}"

# --- Upload to CurseForge ---
echo "==> Uploading to CurseForge..."

METADATA=$(cat <<EOF
{
  "changelog": $(echo "${CHANGELOG}" | jq -Rs .),
  "changelogType": "markdown",
  "displayName": "${ADDON_NAME} ${VERSION}",
  "gameVersions": ${GAME_VERSION_IDS},
  "releaseType": "${RELEASE_TYPE}"
}
EOF
)

CF_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "X-Api-Token: ${CF_API_KEY}" \
  -F "metadata=${METADATA}" \
  -F "file=@${ZIP_FILE}" \
  "https://wow.curseforge.com/api/projects/${CF_PROJECT_ID}/upload-file")

CF_HTTP_CODE=$(echo "${CF_RESPONSE}" | tail -1)
CF_BODY=$(echo "${CF_RESPONSE}" | head -n -1)

if [ "${CF_HTTP_CODE}" -eq 200 ]; then
  CF_FILE_ID=$(echo "${CF_BODY}" | jq -r '.id')
  echo "==> CurseForge upload SUCCESS! File ID: ${CF_FILE_ID}"
else
  echo "ERROR: CurseForge upload failed (HTTP ${CF_HTTP_CODE})"
  echo "${CF_BODY}"
  exit 1
fi

# --- Upload to Wago (optional) ---
if [ -n "${WAGO_API_TOKEN}" ] && [ -n "${WAGO_PROJECT_ID}" ]; then
  echo "==> Uploading to Wago Addons..."

  WAGO_METADATA=$(cat <<EOF2
{
  "label": "${VERSION}",
  "stability": "$(echo "${RELEASE_TYPE}" | sed 's/release/stable/')",
  "changelog": $(echo "${CHANGELOG}" | jq -Rs .),
  "supported_retail_patch": "12.0.0"
}
EOF2
)

  WAGO_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${WAGO_API_TOKEN}" \
    -H "Accept: application/json" \
    -F "metadata=${WAGO_METADATA}" \
    -F "file=@${ZIP_FILE}" \
    "https://addons.wago.io/api/projects/${WAGO_PROJECT_ID}/version")

  WAGO_HTTP_CODE=$(echo "${WAGO_RESPONSE}" | tail -1)
  WAGO_BODY=$(echo "${WAGO_RESPONSE}" | head -n -1)

  if [ "${WAGO_HTTP_CODE}" -eq 200 ] || [ "${WAGO_HTTP_CODE}" -eq 201 ]; then
    echo "==> Wago upload SUCCESS!"
  else
    echo "WARNING: Wago upload failed (HTTP ${WAGO_HTTP_CODE})"
    echo "${WAGO_BODY}"
  fi
fi

echo ""
echo "==> Release ${VERSION} complete!"
```

#### Usage

```bash
# Set your tokens
export CF_API_KEY="your-curseforge-token"
export CF_PROJECT_ID="123456"

# Optional: Wago
export WAGO_API_TOKEN="your-wago-token"
export WAGO_PROJECT_ID="abcdef12"

# Run
chmod +x release-local.sh
./release-local.sh 1.0.0 release
```

#### Simpler Alternative: Use BigWigsMods Packager Locally

You can also run the BigWigsMods packager script directly on your local machine:

```bash
# Download and run the packager
curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | bash

# Or download it once and reuse
curl -o release.sh https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh
chmod +x release.sh

# Run with dry-run (no upload)
./release.sh -d

# Run with CurseForge upload
export CF_API_KEY="your-token"
./release.sh

# Run with specific project IDs (overrides TOC)
./release.sh -p 123456 -a abcdef12
```

**Requirements for local BigWigsMods packager:**
- Bash 4.3+
- Git 2.13.0+
- Standard Unix tools (awk, grep, sed, curl, zip)
- jq 1.5+ (for uploading)

On WSL2 (which MacroPlus is developed on), all these are available or easily installable:

```bash
sudo apt-get install jq zip curl
```

---

### 9. Direct curl Upload (Minimal Example)

For the simplest possible manual upload without any tooling:

```bash
#!/usr/bin/env bash

# Variables
CF_TOKEN="your-api-token"
PROJECT_ID="123456"
ZIP_FILE="MacroPlus-1.0.0.zip"
GAME_VERSION_ID=12345   # Get this from the game versions API

# Upload
curl -X POST \
  -H "X-Api-Token: ${CF_TOKEN}" \
  -F "metadata={\"changelog\":\"Initial release\",\"changelogType\":\"text\",\"gameVersions\":[${GAME_VERSION_ID}],\"releaseType\":\"release\"}" \
  -F "file=@${ZIP_FILE}" \
  "https://wow.curseforge.com/api/projects/${PROJECT_ID}/upload-file"
```

To find game version IDs:

```bash
curl -s -H "X-Api-Token: ${CF_TOKEN}" \
  "https://wow.curseforge.com/api/game/versions" | jq '.[] | select(.name | contains("12"))'
```

---

## Comparative Analysis

### Approach Comparison

| Approach | Setup Effort | Automation | Multi-Platform | Changelog | Recommended For |
|----------|-------------|------------|----------------|-----------|-----------------|
| **BigWigsMods + GitHub Actions** | Medium (one-time) | Fully automatic on tag push | CurseForge + Wago + WoWInterface + GitHub | Auto from git | Production addons (RECOMMENDED) |
| **itsmeow/curseforge-upload Action** | Medium | Automatic but CurseForge only | CurseForge only | Manual | CurseForge-only projects |
| **Local release.sh (BigWigsMods)** | Low | Manual trigger, auto packaging | All platforms | Auto from git | Quick local releases |
| **Custom bash script** | High | Manual | Custom per platform | Manual | Full control needed |
| **Direct curl** | Very low | Fully manual | One platform at a time | Manual | One-off uploads, debugging |

### BigWigsMods Packager vs. Custom Script

| Feature | BigWigsMods Packager | Custom Script |
|---------|---------------------|---------------|
| Changelog generation | Automatic from git tags | Must implement manually |
| Version detection | Automatic from tags | Manual parameter |
| String replacements | `@project-version@` etc. | Must implement with sed |
| Multi-platform upload | Built-in | Must implement each API |
| External libraries | Full checkout support | Not applicable |
| Game version mapping | Automatic from TOC Interface | Must query API manually |
| Nolib packages | Built-in (`-s`) | Not applicable |
| Community support | Widely used, well tested | Self-maintained |
| .pkgmeta support | Full | Not applicable |

**Verdict:** Use the BigWigsMods packager. There is no good reason to build a custom solution unless you have very unusual requirements.

---

## Recommendations

### 1. Use BigWigsMods/packager with GitHub Actions (Confidence: HIGH)

This is the standard, battle-tested approach used by the vast majority of WoW addon authors. Set it up once and every release is a single `git tag` + `git push` command.

### 2. Create a CurseForge project now, even if not ready to release (Confidence: HIGH)

Project approval can take time. Submit the project early so you have your project ID ready when you want to release. You can mark early uploads as `alpha`.

### 3. Also publish to Wago Addons (Confidence: MEDIUM)

Wago is the platform behind WoWUp, which is a popular addon manager. The BigWigsMods packager supports it natively with zero additional workflow configuration -- just add `X-Wago-ID` to your TOC and `WAGO_API_TOKEN` to your secrets.

### 4. Use `@project-version@` in your TOC (Confidence: HIGH)

This lets the packager automatically stamp the correct version from your git tag. You never have to manually update the version string.

### 5. Use annotated git tags with semantic versioning (Confidence: HIGH)

```bash
git tag -a v1.0.0 -m "First stable release"
```

The annotated tag message can serve as a release summary. Semantic versioning (`major.minor.patch`) is well understood by users and tools.

### 6. Keep the local release script as a backup (Confidence: MEDIUM)

Having `release-local.sh` or the ability to run BigWigsMods packager locally is useful for debugging upload issues or making emergency releases when GitHub Actions is down.

---

## Project-Specific Considerations for MacroPlus

### Files to Exclude from Release Packages

Based on the current repository structure, these files/directories should NOT be in the release zip:

| Path | Reason |
|------|--------|
| `.git/` | Version control (auto-excluded) |
| `.github/` | CI/CD configuration |
| `.claude/` | Claude AI configuration |
| `.env` | Local environment secrets |
| `.env-example` | Development setup file |
| `.gitignore` | Git configuration |
| `CLAUDE.md` | Development documentation |
| `README.md` | GitHub documentation (not needed in addon) |
| `deploy.sh` | Local deployment script |
| `release-local.sh` | Local release script |
| `docs/` | Documentation directory |
| `scrape/` | Web scraping scripts |
| `screenshots/` | GitHub screenshots |
| `gemini/` | AI-related files |

### Files that MUST be in the Release Package

| Path | Reason |
|------|--------|
| `MacroPlus.toc` | Addon manifest (required by WoW) |
| `Core/*.lua` | Core addon code |
| `Engine/*.lua` | Engine code |
| `UI/*.lua` | UI code |
| `Data/*.lua` | Data files |

### Interface Version

MacroPlus uses `## Interface: 120000` (WoW 12.0.0 Midnight). The BigWigsMods packager will automatically map this to the correct CurseForge game version IDs. No manual version ID lookup is needed.

### No External Dependencies

MacroPlus is "LibStub-free by design" with no external library dependencies. This simplifies packaging -- no `externals:` section needed in `.pkgmeta`, and no nolib package creation needed.

### Version String in TOC

The current TOC has `## Version: 0.1.0`. Consider changing to `## Version: @project-version@` so the packager auto-stamps it. If you want the version to work during local development too, you can use a build-type conditional:

```
## Version: @project-version@
```

During local development, the literal `@project-version@` string appears in the version field, which is harmless. In packaged releases, it becomes `v1.0.0`.

---

## Caveats and Limitations

### CurseForge Project Approval

New CurseForge projects require manual review and approval. This process can take anywhere from a few hours to several days. Plan ahead and submit your project before you need to release.

### CurseForge API Token URL

The API token page is at `https://www.curseforge.com/account/api-tokens`. This URL has changed in the past as CurseForge has migrated between platforms (from Twitch/Curse to Overwolf). If the URL stops working, check the CurseForge support documentation.

### Game Version IDs Are Dynamic

CurseForge game version IDs are not hardcoded constants -- they change with each new patch. The BigWigsMods packager queries the API automatically to resolve them from your `## Interface:` line. If you are writing a custom script, you must query the game versions API each time.

### WoWInterface Status

WoWInterface has been less actively maintained in recent years. While the BigWigsMods packager still supports it, many addon authors focus on CurseForge and Wago as their primary distribution platforms. Including WoWInterface is optional and lower priority.

### The "CurseForge for Studios API" is Different

Do not confuse the **Upload API** (for addon authors, at `wow.curseforge.com/api/...`) with the **CurseForge for Studios API** (for game developers, at `api.curseforge.com`). They are different APIs with different authentication methods and purposes.

### BigWigsMods Packager v2 vs v1

Always use `BigWigsMods/packager@v2` in your GitHub Actions workflow. Version 2 includes important improvements for multi-game-version support, comma-separated interface values, and better error handling.

### WSL2 Path Considerations

Since MacroPlus is developed on WSL2, note that the local release script and BigWigsMods packager will run natively in the WSL2 Linux environment. The generated zip file will be in Linux format, which is what CurseForge expects.

---

## References and Further Reading

### Official Documentation
- [CurseForge Upload API Documentation](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api)
- [CurseForge API Token Generation](https://www.curseforge.com/account/api-tokens)
- [CurseForge Project Creation Guide](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project)
- [Wago Addons API Documentation](https://docs.wago.io/)
- [Wago API Key Generation](https://addons.wago.io/account/apikeys)

### Tools
- [BigWigsMods/packager (GitHub)](https://github.com/BigWigsMods/packager) -- The standard WoW addon packager
- [BigWigsMods/packager Wiki: GitHub Actions Workflow](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow)
- [BigWigsMods/packager Wiki: Preparing the PackageMeta File](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File)
- [WoW Packager (GitHub Marketplace Action)](https://github.com/marketplace/actions/wow-packager)
- [itsmeow/curseforge-upload (GitHub Action)](https://github.com/itsmeow/curseforge-upload)

### Community Guides
- [Using the BigWigs Packager with GitHub Actions (Wowpedia)](https://wowpedia.fandom.com/wiki/Using_the_BigWigs_Packager_with_GitHub_Actions)
- [Creating Addon Releases with GitHub Actions (Blizzard Forums)](https://us.forums.blizzard.com/en/wow/t/creating-addon-releases-with-github-actions/613424)
- [WoW Addon Template (GitHub)](https://github.com/layday/wow-addon-template) -- Reference template with CI/CD

### Other Tools
- [wow-addon-packager (PyPI)](https://pypi.org/project/wow-addon-packager/) -- Python-based alternative
- [wow-build-tools (CurseForge)](https://www.curseforge.com/wow/addons/wow-build-tools) -- Drop-in packager replacement

---

## Appendix A: Complete File Listing for MacroPlus Release Setup

Below is every file you need to create or modify, with complete contents.

### File 1: `.pkgmeta` (NEW -- create in repo root)

```yaml
package-as: MacroPlus

ignore:
  - .github
  - .gitignore
  - .gitattributes
  - .env
  - .env-example
  - .luacheckrc
  - .pkgmeta
  - .claude
  - CLAUDE.md
  - README.md
  - LICENSE
  - deploy.sh
  - release-local.sh
  - docs
  - scrape
  - screenshots
  - gemini
```

### File 2: `.github/workflows/release.yml` (NEW)

```yaml
name: Package and Release

on:
  push:
    tags:
      - "v*"
      - "[0-9]*"

jobs:
  release:
    runs-on: ubuntu-latest

    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}

    steps:
      - name: Clone project
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Package and release
        uses: BigWigsMods/packager@v2
```

### File 3: `MacroPlus.toc` (MODIFY -- add project IDs and version token)

```
## Interface: 120000
## Title: MacroPlus
## Notes: Cross-character macro library with IDE-style editor and slash-command encyclopedia
## Author: Big-Bro-Bot
## Version: @project-version@
## SavedVariables: MMO_GlobalDB
## X-Curse-Project-ID: REPLACE_WITH_YOUR_PROJECT_ID
## X-Wago-ID: REPLACE_WITH_YOUR_WAGO_ID

Core\Init.lua
Core\Database.lua
Core\CombatLock.lua
Engine\Scraper.lua
Engine\ImportExport.lua
Engine\Sharing.lua
UI\MainFrame.lua
UI\Sidebar.lua
UI\MacroGrid.lua
UI\SearchBar.lua
UI\Editor.lua
UI\ShareDialog.lua
Engine\Sync.lua
Data\SlashCommands.lua
Data\Conditions.lua
Data\SpecialCommands.lua
Engine\Parser.lua
Engine\Shortener.lua
UI\CommandPanel.lua
UI\ConditionBuilder.lua
```

### File 4: `.gitignore` (MODIFY -- add release artifacts)

Add these lines to your existing `.gitignore`:

```
# Release artifacts
.release/
*.zip
```

---

## Appendix B: Release Checklist

Use this checklist for your first release:

1. [ ] Create CurseForge project at https://www.curseforge.com/project/create
2. [ ] Wait for CurseForge project approval
3. [ ] Note your CurseForge project ID from the project sidebar
4. [ ] Generate CurseForge API token at https://www.curseforge.com/account/api-tokens
5. [ ] (Optional) Create Wago Addons project at https://addons.wago.io
6. [ ] (Optional) Generate Wago API key at https://addons.wago.io/account/apikeys
7. [ ] Update `MacroPlus.toc` with `X-Curse-Project-ID` and optionally `X-Wago-ID`
8. [ ] Create `.pkgmeta` file in repo root
9. [ ] Create `.github/workflows/release.yml`
10. [ ] Add `CF_API_KEY` secret to GitHub repository settings
11. [ ] (Optional) Add `WAGO_API_TOKEN` secret to GitHub repository settings
12. [ ] Configure GITHUB_TOKEN permissions (Settings > Actions > General > Read and write)
13. [ ] Update `.gitignore` to exclude `.release/` and `*.zip`
14. [ ] Commit all changes
15. [ ] Create and push your first tag:
    ```bash
    git tag -a v1.0.0 -m "First release"
    git push origin v1.0.0
    ```
16. [ ] Monitor the GitHub Actions run at your repo's Actions tab
17. [ ] Verify the release appears on CurseForge, Wago, and GitHub Releases

---

## Appendix C: Troubleshooting

### "Resource not accessible by integration" error on GitHub Release

**Cause:** The `GITHUB_TOKEN` does not have write permissions.
**Fix:** Go to Settings > Actions > General > Workflow permissions > Select "Read and write permissions."

### CurseForge upload returns 403

**Cause:** Invalid or expired API token.
**Fix:** Generate a new token at https://www.curseforge.com/account/api-tokens and update the `CF_API_KEY` secret.

### CurseForge upload returns 422

**Cause:** Invalid metadata (e.g., wrong game version IDs, missing required fields).
**Fix:** If using BigWigsMods packager, ensure your `## Interface:` line in the TOC is correct. If using custom curl, verify game version IDs by querying the API.

### Packager says "No tags found"

**Cause:** The checkout does not have the full git history.
**Fix:** Ensure `fetch-depth: 0` in the `actions/checkout` step (not the default shallow clone).

### Packager creates wrong version number

**Cause:** Tag format does not match expectations.
**Fix:** Use annotated tags: `git tag -a v1.0.0 -m "Release"`. Lightweight tags also work but annotated tags are more reliable.

### Zip contains wrong files or extra files

**Cause:** `.pkgmeta` ignore list is incomplete.
**Fix:** Add missing entries to the `ignore:` section. Run the packager locally with `-d` (no upload) to inspect the zip contents: `bash release.sh -d`.

#!/bin/bash

# Load environment variables
if [ ! -f .env ]; then
  echo "Error: .env file not found. Copy .env-example to .env and set your WoW path."
  exit 1
fi

source .env

if [ -z "$WOW_ADDONS_PATH" ]; then
  echo "Error: WOW_ADDONS_PATH is not set in .env"
  exit 1
fi

ADDON_NAME="MacroPlus"
DEST="$WOW_ADDONS_PATH/$ADDON_NAME"
BACKUP_DIR="$DEST/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DEST="$BACKUP_DIR/$TIMESTAMP"

# Backup existing addon files if the folder already exists
if [ -d "$DEST" ]; then
  echo "Backing up current version to: $BACKUP_DEST"
  mkdir -p "$BACKUP_DEST"
  rsync -a \
    --exclude='backups/' \
    "$DEST/" "$BACKUP_DEST/"
  echo "Backup complete."

  # Remove everything in DEST except the backups folder
  find "$DEST" -mindepth 1 -maxdepth 1 ! -name 'backups' -exec rm -rf {} +
  echo "Cleaned old files."
else
  mkdir -p "$DEST"
fi

# Deploy new files
echo "Deploying $ADDON_NAME to: $DEST"
rsync -av \
  --exclude='.git/' \
  --exclude='.claude/' \
  --exclude='.env' \
  --exclude='.env-example' \
  --exclude='.gitignore' \
  --exclude='deploy.sh' \
  --exclude='README.md' \
  --exclude='CLAUDE.md' \
  ./ "$DEST/"

echo "Done."

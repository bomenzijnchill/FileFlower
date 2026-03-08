#!/usr/bin/env bash
set -euo pipefail

# Pad naar de bron (project) en doel (CEP extensie)
SRC="/Users/koendijkstra/FileFlower/PremierePlugin_CEP/"
DEST="/Users/koendijkstra/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge/"

if [[ ! -d "$SRC" ]]; then
  echo "Bronmap bestaat niet: $SRC"
  exit 1
fi

if [[ ! -d "$DEST" ]]; then
  echo "Doelmap bestaat niet: $DEST"
  exit 1
fi

echo "Wijzig eigenaar naar $USER (sudo nodig)..."
sudo chown -R "$USER":staff "$DEST"

echo "Sync bestanden naar CEP extensie..."
rsync -av --delete --exclude=".DS_Store" "$SRC" "$DEST"

echo "Klaar. Herstart Premiere/CEP indien nodig."




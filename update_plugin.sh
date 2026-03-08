#!/bin/bash

# Script om de Premiere plugin te updaten

SOURCE_FILE="PremierePlugin_CEP/index.js"
TARGET_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge"
BRIDGE_SOURCE="PremierePlugin_CEP/jsx/bridge.jsx"
BRIDGE_TARGET="$TARGET_DIR/jsx/bridge.jsx"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "Fout: Bronbestand niet gevonden: $SOURCE_FILE"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Fout: Doeldirectory niet gevonden: $TARGET_DIR"
    exit 1
fi

echo "Updaten van plugin in $TARGET_DIR..."

# Update index.js
if sudo cp "$SOURCE_FILE" "$TARGET_DIR/index.js"; then
    echo "✓ index.js geüpdatet"
else
    echo "Fout bij updaten index.js. Probeer handmatig:"
    echo "sudo cp $SOURCE_FILE \"$TARGET_DIR/index.js\""
    exit 1
fi

# Update bridge.jsx if it exists
if [ -f "$BRIDGE_SOURCE" ]; then
    if sudo cp "$BRIDGE_SOURCE" "$BRIDGE_TARGET"; then
        echo "✓ bridge.jsx geüpdatet"
    else
        echo "Waarschuwing: bridge.jsx kon niet worden geüpdatet"
    fi
fi

echo ""
echo "Plugin succesvol geüpdatet!"
echo "Herstart Premiere Pro om de wijzigingen te laden."

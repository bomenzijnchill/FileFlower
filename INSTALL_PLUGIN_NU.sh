#!/bin/bash
# Snelle installatie van CEP plugin
# Voer uit: sudo bash INSTALL_PLUGIN_NU.sh

set -e

PLUGIN_SOURCE="/Users/koendijkstra/FileFlower_V2/PremierePlugin_CEP"
PLUGIN_DEST="$HOME/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge"
CSINTERFACE_SOURCE="/Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js"

echo "📦 FileFlower CEP Plugin Installatie"
echo "========================================"
echo ""

# Check source
if [ ! -d "$PLUGIN_SOURCE" ]; then
    echo "❌ Fout: Plugin source niet gevonden: $PLUGIN_SOURCE"
    exit 1
fi

# Maak directory
echo "📁 Directory aanmaken..."
mkdir -p "$HOME/Library/Application Support/Adobe/CEP/extensions"

# Verwijder oude
if [ -d "$PLUGIN_DEST" ]; then
    echo "🗑️  Verwijderen oude versie..."
    rm -rf "$PLUGIN_DEST"
fi

# Kopieer
echo "📋 Kopiëren plugin..."
cp -r "$PLUGIN_SOURCE" "$PLUGIN_DEST"

# CSInterface.js
if [ -f "$CSINTERFACE_SOURCE" ]; then
    echo "📋 Kopiëren CSInterface.js..."
    cp "$CSINTERFACE_SOURCE" "$PLUGIN_DEST/CSInterface.js"
else
    echo "⚠️  CSInterface.js niet gevonden op $CSINTERFACE_SOURCE"
fi

# Permissions
echo "🔐 Permissions instellen..."
chmod -R 755 "$PLUGIN_DEST"

# Verifieer
echo ""
echo "🔍 Verificatie..."
if [ -f "$PLUGIN_DEST/CSXS/manifest.xml" ]; then
    echo "✅ Plugin geïnstalleerd!"
    echo ""
    echo "📍 Locatie: $PLUGIN_DEST"
    echo ""
    echo "📝 Volgende stappen:"
    echo "1. Herstart Premiere Pro volledig"
    echo "2. Ga naar: Window > Extensions > FileFlower Bridge"
    echo "3. Zorg dat macOS app draait (HTTP server op localhost:17890)"
else
    echo "❌ Installatie gefaald!"
    exit 1
fi


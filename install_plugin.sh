#!/bin/bash
# FileFlower CEP Plugin Installatie Script
# Voer dit script uit in Terminal

set -e

PLUGIN_SOURCE="/Users/koendijkstra/FileFlower_V2/PremierePlugin_CEP"
PLUGIN_DEST="$HOME/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge"
CSINTERFACE_SOURCE="/Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js"

echo "📦 FileFlower CEP Plugin Installatie"
echo "========================================"
echo ""

# Check of source bestaat
if [ ! -d "$PLUGIN_SOURCE" ]; then
    echo "❌ Fout: Plugin source niet gevonden: $PLUGIN_SOURCE"
    exit 1
fi

# Maak CEP extensions directory aan
echo "📁 CEP extensions directory aanmaken..."
mkdir -p "$HOME/Library/Application Support/Adobe/CEP/extensions"

# Verwijder oude versie als die bestaat
if [ -d "$PLUGIN_DEST" ]; then
    echo "🗑️  Verwijderen oude plugin versie..."
    rm -rf "$PLUGIN_DEST"
fi

# Kopieer plugin
echo "📋 Kopiëren plugin bestanden..."
cp -r "$PLUGIN_SOURCE" "$PLUGIN_DEST"

# Kopieer CSInterface.js als die nog niet bestaat
if [ ! -f "$PLUGIN_DEST/CSInterface.js" ] && [ -f "$CSINTERFACE_SOURCE" ]; then
    echo "📋 Kopiëren CSInterface.js..."
    cp "$CSINTERFACE_SOURCE" "$PLUGIN_DEST/CSInterface.js"
elif [ ! -f "$PLUGIN_DEST/CSInterface.js" ]; then
    echo "⚠️  Waarschuwing: CSInterface.js niet gevonden op $CSINTERFACE_SOURCE"
    echo "   Je moet dit handmatig kopiëren van je oude plugin"
fi

# Fix permissions
echo "🔐 Permissions instellen..."
chmod -R 755 "$PLUGIN_DEST"

# Verifieer installatie
echo ""
echo "🔍 Verificatie..."
if [ -d "$PLUGIN_DEST" ] && [ -f "$PLUGIN_DEST/CSXS/manifest.xml" ]; then
    echo "✅ Plugin succesvol geïnstalleerd!"
    echo ""
    echo "Geïnstalleerde bestanden:"
    ls -la "$PLUGIN_DEST" | head -15
    echo ""
    echo "📝 Volgende stappen:"
    echo "1. Herstart Premiere Pro (als die open is)"
    echo "2. Ga naar: Window > Extensions > FileFlower Bridge"
    echo "3. Zorg dat de macOS app draait (HTTP server op localhost:17890)"
    echo ""
    
    # Check CSInterface.js
    if [ -f "$PLUGIN_DEST/CSInterface.js" ]; then
        echo "✅ CSInterface.js aanwezig"
    else
        echo "⚠️  CSInterface.js ontbreekt - kopieer handmatig:"
        echo "   cp $CSINTERFACE_SOURCE $PLUGIN_DEST/CSInterface.js"
    fi
else
    echo "❌ Installatie gefaald - controleer errors hierboven"
    exit 1
fi


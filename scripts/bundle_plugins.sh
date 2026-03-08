#!/bin/bash
# Script om te verifiëren dat plugins aanwezig zijn
# De daadwerkelijke bundeling gebeurt nu in build_dmg.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PREMIERE_PLUGIN_SRC="$PROJECT_ROOT/PremierePlugin_CEP"
CHROME_EXTENSION_SRC="$PROJECT_ROOT/ChromeExtension"

echo "📦 Plugin verificatie..."
echo "   Project root: $PROJECT_ROOT"
echo ""

# Check Premiere Plugin
if [ -d "$PREMIERE_PLUGIN_SRC" ]; then
    echo "   ✅ PremierePlugin gevonden: $PREMIERE_PLUGIN_SRC"
else
    echo "   ❌ PremierePlugin NIET gevonden: $PREMIERE_PLUGIN_SRC"
    exit 1
fi

# Check Chrome Extension
if [ -d "$CHROME_EXTENSION_SRC" ]; then
    echo "   ✅ ChromeExtension gevonden: $CHROME_EXTENSION_SRC"
else
    echo "   ❌ ChromeExtension NIET gevonden: $CHROME_EXTENSION_SRC"
    exit 1
fi

# Check Safari Extension project
SAFARI_PROJECT="$PROJECT_ROOT/SafariExtension/FileFlower Safari/FileFlower Safari.xcodeproj"
if [ -d "$SAFARI_PROJECT" ]; then
    echo "   ✅ Safari extensie project gevonden: $SAFARI_PROJECT"
else
    echo "   ❌ Safari extensie project NIET gevonden: $SAFARI_PROJECT"
    exit 1
fi

echo ""
echo "✅ Alle plugins aanwezig!"
echo "   (Plugins worden gebundeld tijdens build_dmg.sh)"
echo ""


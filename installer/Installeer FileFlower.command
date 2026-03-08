#!/bin/bash
# FileFlower Installer Script
# Dubbelklik op dit bestand om de app te installeren

clear
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              FileFlower Installatie                            ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Bepaal waar de DMG is gemount
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/FileFlower.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ FOUT: FileFlower.app niet gevonden!"
    echo ""
    echo "Zorg dat je dit script uitvoert vanuit de DMG."
    echo ""
    read -p "Druk op Enter om te sluiten..."
    exit 1
fi

echo "📦 FileFlower.app gevonden"
echo ""

# Kopieer naar Applications
echo "📁 Kopiëren naar Applications map..."
if [ -d "/Applications/FileFlower.app" ]; then
    echo "   (Oude versie wordt verwijderd...)"
    rm -rf "/Applications/FileFlower.app"
fi

cp -R "$APP_PATH" "/Applications/"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ FOUT: Kon niet kopiëren naar Applications."
    echo "   Probeer handmatig te slepen naar de Applications map."
    echo ""
    read -p "Druk op Enter om te sluiten..."
    exit 1
fi

echo "✅ App gekopieerd naar /Applications/"
echo ""

# Verwijder quarantine attribuut
echo "🔓 Quarantine attribuut verwijderen..."
xattr -cr "/Applications/FileFlower.app"
echo "✅ Quarantine verwijderd"
echo ""

# Open de app
echo "🚀 App starten..."
open "/Applications/FileFlower.app"

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "✅ INSTALLATIE VOLTOOID!"
echo ""
echo "De app is geïnstalleerd en geopend."
echo "Je kunt dit venster nu sluiten."
echo "════════════════════════════════════════════════════════════════════"
echo ""
read -p "Druk op Enter om te sluiten..."


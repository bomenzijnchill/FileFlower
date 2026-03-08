#!/bin/bash
# Genereer alle app icon formaten van een source afbeelding
# Gebruik: ./scripts/generate_icons.sh /pad/naar/source_icon.png

set -e

if [ -z "$1" ]; then
    echo "Gebruik: $0 /pad/naar/source_icon.png"
    echo ""
    echo "De source afbeelding moet minimaal 1024x1024 pixels zijn."
    exit 1
fi

SOURCE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ICONSET_DIR="$PROJECT_ROOT/FileFlower/FileFlower/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
    echo "❌ Bestand niet gevonden: $SOURCE"
    exit 1
fi

echo "🎨 App iconen genereren..."
echo "   Source: $SOURCE"
echo "   Output: $ICONSET_DIR"
echo ""

# Genereer alle benodigde formaten
sips -z 16 16     "$SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64     "$SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

echo "✅ Iconen gegenereerd!"
echo ""
echo "📁 Gegenereerde bestanden:"
ls -la "$ICONSET_DIR"/*.png
echo ""



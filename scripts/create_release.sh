#!/bin/bash
# GitHub Release Script voor FileFlower
# Maakt een nieuwe release aan op GitHub
#
# Vereisten:
# - GitHub CLI (gh): brew install gh
# - GitHub authenticatie: gh auth login
#
# Gebruik:
# ./scripts/create_release.sh

set -e

# Configuratie
GITHUB_REPO="bomenzijnchill/FileFlower"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
PBXPROJ="$PROJECT_ROOT/FileFlower/FileFlower.xcodeproj/project.pbxproj"
APPCAST_FILE="$PROJECT_ROOT/appcast.xml"

# Kleuren
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "   FileFlower GitHub Release"
echo "========================================="
echo ""

error_exit() {
    echo -e "${RED}❌ FOUT: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check gh CLI
if ! command -v gh &> /dev/null; then
    error_exit "GitHub CLI (gh) niet gevonden. Installeer met: brew install gh"
fi

# Check authenticatie
if ! gh auth status &> /dev/null; then
    error_exit "GitHub CLI niet geauthenticeerd. Voer uit: gh auth login"
fi

# Lees huidige versie uit project.pbxproj
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;.*//' | tr -d ' ')
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= //;s/;.*//' | tr -d ' ')

info "Huidige versie in project: $CURRENT_VERSION (build $CURRENT_BUILD)"

# Zoek DMG in dist folder
DMG_FILE=$(ls -t "$DIST_DIR"/*.dmg 2>/dev/null | head -1)
if [ -z "$DMG_FILE" ]; then
    error_exit "Geen DMG gevonden in $DIST_DIR. Voer eerst build_dmg.sh uit."
fi

DMG_NAME=$(basename "$DMG_FILE")
info "DMG gevonden: $DMG_NAME"

# Gebruik versie uit project.pbxproj
VERSION="$CURRENT_VERSION"
BUILD="$CURRENT_BUILD"

echo ""
echo -n "Versie $VERSION (build $BUILD) gebruiken? (y/n): "
read USE_VERSION

if [ "$USE_VERSION" != "y" ] && [ "$USE_VERSION" != "Y" ]; then
    echo -n "Versie nummer (bijv. 1.2.1): "
    read VERSION
    echo -n "Build nummer (bijv. 3): "
    read BUILD
fi

info "Versie: v$VERSION (build $BUILD)"

# Release notes
echo ""
echo "📝 Voer release notes in (eindig met een lege regel):"
RELEASE_NOTES=""
while IFS= read -r line; do
    [ -z "$line" ] && break
    RELEASE_NOTES="$RELEASE_NOTES$line"$'\n'
done

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="Release v$VERSION"
fi

# Bestandsgrootte
FILE_SIZE=$(stat -f%z "$DMG_FILE")
info "Bestandsgrootte: $FILE_SIZE bytes"

# EdDSA signing
echo ""
echo "🔑 DMG signen voor Sparkle..."
BUILD_DIR="$PROJECT_ROOT/build"
SPARKLE_SIGN_UPDATE="$BUILD_DIR/SourcePackages/checkouts/Sparkle/bin/sign_update"

if [ ! -f "$SPARKLE_SIGN_UPDATE" ]; then
    SPARKLE_SIGN_UPDATE=$(find "$BUILD_DIR" -name "sign_update" -path "*/Sparkle/*" 2>/dev/null | head -1)
fi

ED_SIGNATURE=""
if [ -f "$SPARKLE_SIGN_UPDATE" ]; then
    SIGN_OUTPUT=$("$SPARKLE_SIGN_UPDATE" "$DMG_FILE")
    # sign_update output: sparkle:edSignature="..." length="..."
    ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"$//')
    success "DMG gesigned"
    info "Signature: ${ED_SIGNATURE:0:20}..."
else
    warning "sign_update tool niet gevonden."
    echo -n "EdDSA signature (of leeg laten): "
    read ED_SIGNATURE
fi

# Bevestiging
echo ""
echo "📦 Release configuratie:"
echo "   Repository: $GITHUB_REPO"
echo "   Versie: v$VERSION (build $BUILD)"
echo "   Bestand: $DMG_NAME"
echo "   Grootte: $(echo "scale=2; $FILE_SIZE / 1048576" | bc) MB"
if [ -n "$ED_SIGNATURE" ]; then
    echo "   EdDSA: ${ED_SIGNATURE:0:20}..."
fi
echo ""
echo -n "Doorgaan met release? (y/n): "
read CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Geannuleerd."
    exit 0
fi

# Maak release aan
echo ""
echo "🚀 Release aanmaken op GitHub..."

gh release create "v$VERSION" \
    --repo "$GITHUB_REPO" \
    --title "FileFlower v$VERSION" \
    --notes "$RELEASE_NOTES" \
    "$DMG_FILE" \
    || error_exit "GitHub release maken mislukt"

success "Release v$VERSION aangemaakt!"

# Download URL
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$DMG_NAME"

# Genereer appcast entry
ENCLOSURE_ATTRS="url=\"$DOWNLOAD_URL\""
if [ -n "$ED_SIGNATURE" ]; then
    ENCLOSURE_ATTRS="$ENCLOSURE_ATTRS
                sparkle:edSignature=\"$ED_SIGNATURE\""
fi
ENCLOSURE_ATTRS="$ENCLOSURE_ATTRS
                length=\"$FILE_SIZE\"
                type=\"application/octet-stream\""

NEW_ENTRY="        <item>
            <title>Versie $VERSION</title>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                $RELEASE_NOTES
            ]]></description>
            <pubDate>$(date -R)</pubDate>
            <enclosure
                $ENCLOSURE_ATTRS
            />
        </item>"

# Update appcast.xml automatisch
echo ""
echo "📝 Appcast.xml updaten..."

if [ -f "$APPCAST_FILE" ]; then
    # Voeg nieuwe entry in na "<!-- Nieuwste versie bovenaan -->"
    TEMP_APPCAST=$(mktemp)
    awk -v entry="$NEW_ENTRY" '
        /<!-- Nieuwste versie bovenaan -->/ {
            print
            print ""
            print entry
            next
        }
        { print }
    ' "$APPCAST_FILE" > "$TEMP_APPCAST"
    mv "$TEMP_APPCAST" "$APPCAST_FILE"
    success "Appcast.xml bijgewerkt met versie $VERSION"
else
    warning "Appcast.xml niet gevonden op: $APPCAST_FILE"
    echo ""
    echo "========================================="
    echo "📋 Voeg dit toe aan je appcast.xml:"
    echo "========================================="
    echo ""
    echo "$NEW_ENTRY"
fi

echo ""
success "Klaar! Vergeet niet appcast.xml te committen en te pushen."
echo ""

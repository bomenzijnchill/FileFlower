#!/bin/bash
# Notarization Script voor FileFlower
# OPTIONEEL - alleen nodig met Apple Developer Account ($99/jaar)
#
# Notariseert de DMG bij Apple voor Gatekeeper
# Zonder notarization moeten gebruikers rechts-klikken → Open
#
# Vereisten:
# - Apple Developer Account ($99/jaar)
# - App-specific password (voor notarytool)
# - Developer ID Application certificate
#
# Configuratie:
# Stel de volgende environment variabelen in of pas ze hieronder aan:
# - APPLE_ID: Je Apple ID email
# - TEAM_ID: Je Apple Developer Team ID
# - APP_PASSWORD: App-specific password (gemaakt op appleid.apple.com)

set -e

# Configuratie
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
DMG_PATH="$BUILD_DIR/FileFlower.dmg"

# Apple credentials (vul in of gebruik environment variabelen)
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
APP_PASSWORD="${APP_PASSWORD:-xxxx-xxxx-xxxx-xxxx}"

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "   FileFlower Notarization Script"
echo "========================================="
echo ""

# Functie om errors te tonen
error_exit() {
    echo -e "${RED}❌ FOUT: $1${NC}" >&2
    exit 1
}

# Functie om succes te tonen
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Functie om info te tonen
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Functie om waarschuwing te tonen
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check of DMG bestaat
if [ ! -f "$DMG_PATH" ]; then
    error_exit "DMG niet gevonden: $DMG_PATH\nVoer eerst build_dmg.sh uit."
fi

# Check credentials
if [ "$APPLE_ID" = "your-apple-id@example.com" ]; then
    error_exit "APPLE_ID niet geconfigureerd. Stel de environment variabele in of pas het script aan."
fi

if [ "$TEAM_ID" = "YOUR_TEAM_ID" ]; then
    error_exit "TEAM_ID niet geconfigureerd. Stel de environment variabele in of pas het script aan."
fi

if [ "$APP_PASSWORD" = "xxxx-xxxx-xxxx-xxxx" ]; then
    error_exit "APP_PASSWORD niet geconfigureerd. Maak een app-specific password op appleid.apple.com"
fi

echo "📋 Notarization configuratie:"
echo "   Apple ID: $APPLE_ID"
echo "   Team ID: $TEAM_ID"
echo "   DMG: $DMG_PATH"
echo ""

# Stap 1: DMG uploaden voor notarization
echo "📤 Uploaden naar Apple Notary Service..."
info "Dit kan enkele minuten duren..."

SUBMISSION_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait \
    2>&1)

echo "$SUBMISSION_OUTPUT"

# Check of notarization succesvol was
if echo "$SUBMISSION_OUTPUT" | grep -q "status: Accepted"; then
    success "Notarization succesvol!"
    
    # Haal submission ID op voor log
    SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    
    # Toon notarization log (optioneel)
    echo ""
    info "Notarization log ophalen..."
    xcrun notarytool log "$SUBMISSION_ID" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        2>&1 || warning "Kon log niet ophalen"
    
else
    # Toon foutdetails
    SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    
    if [ -n "$SUBMISSION_ID" ]; then
        echo ""
        warning "Notarization gefaald. Log ophalen voor details..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            2>&1
    fi
    
    error_exit "Notarization gefaald"
fi

# Stap 2: Staple de notarization ticket aan de DMG
echo ""
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH" || error_exit "Stapling gefaald"

success "Notarization ticket gestapled!"

# Stap 3: Verificatie
echo ""
echo "🔍 Verificatie..."
xcrun stapler validate "$DMG_PATH" || error_exit "Validatie gefaald"

success "Validatie succesvol!"

# Spago verify
echo ""
info "Gatekeeper verificatie..."
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 || warning "Spctl check kon niet worden uitgevoerd"

# Toon resultaat
echo ""
echo "========================================="
echo -e "${GREEN}   ✅ NOTARIZATION VOLTOOID${NC}"
echo "========================================="
echo ""
echo "📍 Genotariseerde DMG: $DMG_PATH"
echo ""
echo "📝 De DMG is nu klaar voor distributie:"
echo "   - Gebruikers kunnen de app installeren zonder Gatekeeper waarschuwingen"
echo "   - De app wordt herkend als afkomstig van een geïdentificeerde ontwikkelaar"
echo ""

# Toon bestandsgrootte
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "📊 DMG grootte: $DMG_SIZE"
echo ""

# Kopieer naar output map voor distributie
OUTPUT_DIR="$PROJECT_ROOT/dist"
mkdir -p "$OUTPUT_DIR"
cp "$DMG_PATH" "$OUTPUT_DIR/"
success "DMG gekopieerd naar: $OUTPUT_DIR/$(basename "$DMG_PATH")"
echo ""


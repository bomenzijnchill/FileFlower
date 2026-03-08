#!/bin/bash
# DMG Build Script voor FileFlower
# Bouwt een gesignde en genotariseerde DMG voor distributie
#
# Vereisten:
# - Xcode Command Line Tools
# - create-dmg (brew install create-dmg)
# - Developer ID Application certificaat
# - Notarisatie credentials opgeslagen via: xcrun notarytool store-credentials "FileFlower"

set -e

# Configuratie
APP_NAME="FileFlower"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
XCODE_PROJECT="$PROJECT_ROOT/FileFlower/FileFlower.xcodeproj"
SAFARI_XCODE_PROJECT="$PROJECT_ROOT/SafariExtension/FileFlower Safari/FileFlower Safari.xcodeproj"
BUILD_DIR="$PROJECT_ROOT/build"
SAFARI_BUILD_DIR="$PROJECT_ROOT/build_safari"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
SAFARI_APP_PATH="$SAFARI_BUILD_DIR/Build/Products/Release/FileFlower Safari.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "   FileFlower DMG Build Script"
echo "   (met Developer ID signing + notarisatie)"
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

# Functie om waarschuwing te tonen
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Functie om info te tonen
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check vereisten
echo "📋 Controleren vereisten..."

if ! command -v xcodebuild &> /dev/null; then
    error_exit "xcodebuild niet gevonden. Installeer Xcode Command Line Tools."
fi

if ! command -v create-dmg &> /dev/null; then
    warning "create-dmg niet gevonden. Probeer te installeren via brew..."
    if command -v brew &> /dev/null; then
        brew install create-dmg
    else
        error_exit "create-dmg niet gevonden. Installeer met: brew install create-dmg"
    fi
fi

success "Vereisten gevonden"

# Maak build directory aan
echo ""
echo "📁 Build directory voorbereiden..."
rm -rf "$BUILD_DIR"
rm -rf "$SAFARI_BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$SAFARI_BUILD_DIR"
success "Build directory aangemaakt: $BUILD_DIR"

# Bundle plugins voordat we bouwen
echo ""
echo "📦 Bundelen van plugins..."
bash "$SCRIPT_DIR/bundle_plugins.sh"
success "Plugins gebundeld"

# Bouwen (met Developer ID signing)
echo ""
echo "🔨 Bouwen van app (Release mode, met Developer ID signing)..."
xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="Developer ID Application: Koen Dijkstra (JWD857B8TF)" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=JWD857B8TF \
    -quiet \
    || error_exit "Build gefaald"

# Verifieer dat de app bestaat
if [ ! -d "$APP_PATH" ]; then
    error_exit "Gebouwde app niet gevonden: $APP_PATH"
fi

success "App gebouwd: $APP_PATH"

# Bouwen Safari extensie app
echo ""
echo "🔨 Bouwen van Safari extensie app (Release mode)..."
xcodebuild \
    -project "$SAFARI_XCODE_PROJECT" \
    -scheme "FileFlower Safari" \
    -configuration Release \
    -derivedDataPath "$SAFARI_BUILD_DIR" \
    CODE_SIGN_IDENTITY="Developer ID Application: Koen Dijkstra (JWD857B8TF)" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=JWD857B8TF \
    -quiet \
    || error_exit "Safari extensie build gefaald"

if [ ! -d "$SAFARI_APP_PATH" ]; then
    error_exit "Safari extensie app niet gevonden: $SAFARI_APP_PATH"
fi

success "Safari extensie app gebouwd: $SAFARI_APP_PATH"

# Kopieer plugins naar app bundle (behoud mapstructuur)
echo ""
echo "📦 Plugins kopiëren naar app bundle..."
PLUGINS_DEST="$APP_PATH/Contents/Resources"

# Kopieer PremierePlugin
if [ -d "$PROJECT_ROOT/PremierePlugin_CEP" ]; then
    ditto "$PROJECT_ROOT/PremierePlugin_CEP" "$PLUGINS_DEST/PremierePlugin"
    # Verwijder README uit bundle
    rm -f "$PLUGINS_DEST/PremierePlugin/README.md"
    success "PremierePlugin toegevoegd aan bundle"
fi

# Kopieer ChromeExtension
if [ -d "$PROJECT_ROOT/ChromeExtension" ]; then
    ditto "$PROJECT_ROOT/ChromeExtension" "$PLUGINS_DEST/ChromeExtension"
    # Verwijder README uit bundle
    rm -f "$PLUGINS_DEST/ChromeExtension/README.md"
    success "ChromeExtension toegevoegd aan bundle"
fi

# Kopieer ResolvePlugin (Python bridge script)
if [ -d "$PROJECT_ROOT/ResolvePlugin" ]; then
    ditto "$PROJECT_ROOT/ResolvePlugin" "$PLUGINS_DEST/ResolvePlugin"
    rm -f "$PLUGINS_DEST/ResolvePlugin/README.md"
    success "ResolvePlugin toegevoegd aan bundle"
fi

# Kopieer Safari extensie app
if [ -d "$SAFARI_APP_PATH" ]; then
    ditto "$SAFARI_APP_PATH" "$PLUGINS_DEST/FileFlower Safari.app"
    success "FileFlower Safari.app toegevoegd aan bundle"
fi

# Re-sign de app na het toevoegen van plugins
# BELANGRIJK: Sign van binnen naar buiten (binnenste componenten eerst)
# BELANGRIJK: --timestamp is vereist voor notarisatie
echo ""
echo "🔏 App opnieuw signen na plugin bundeling..."
ENTITLEMENTS="$PROJECT_ROOT/FileFlower/FileFlower/FileFlower.entitlements"
FINDER_SYNC_ENTITLEMENTS="$PROJECT_ROOT/FileFlower/FileFlowerFinderSync/FileFlowerFinderSync.entitlements"
SAFARI_APP_ENTITLEMENTS="$PROJECT_ROOT/SafariExtension/FileFlower Safari/FileFlower Safari/FileFlower Safari.entitlements"
SAFARI_EXT_ENTITLEMENTS="$PROJECT_ROOT/SafariExtension/FileFlower Safari/FileFlower Safari Extension/FileFlower Safari Extension.entitlements"
SIGNING_IDENTITY="Developer ID Application: Koen Dijkstra (JWD857B8TF)"
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
APPEX="$APP_PATH/Contents/PlugIns/FileFlowerFinderSync.appex"

# Stap 1: Sign Sparkle XPC Services
if [ -d "$SPARKLE_FW/Versions/B/XPCServices" ]; then
    info "Signen van Sparkle XPC Services..."
    for xpc in "$SPARKLE_FW/Versions/B/XPCServices/"*.xpc; do
        if [ -d "$xpc" ]; then
            codesign --force --sign "$SIGNING_IDENTITY" \
                --timestamp --options runtime \
                "$xpc" \
                || error_exit "Code signing gefaald voor $(basename "$xpc")"
            success "  $(basename "$xpc") gesigned"
        fi
    done
fi

# Stap 2: Sign Sparkle Updater.app
if [ -d "$SPARKLE_FW/Versions/B/Updater.app" ]; then
    info "Signen van Sparkle Updater.app..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        "$SPARKLE_FW/Versions/B/Updater.app" \
        || error_exit "Code signing gefaald voor Updater.app"
    success "  Updater.app gesigned"
fi

# Stap 3: Sign Sparkle Autoupdate binary
if [ -f "$SPARKLE_FW/Versions/B/Autoupdate" ]; then
    info "Signen van Sparkle Autoupdate..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        "$SPARKLE_FW/Versions/B/Autoupdate" \
        || error_exit "Code signing gefaald voor Autoupdate"
    success "  Autoupdate gesigned"
fi

# Stap 4: Sign het Sparkle framework zelf
if [ -d "$SPARKLE_FW" ]; then
    info "Signen van Sparkle.framework..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        "$SPARKLE_FW" \
        || error_exit "Code signing gefaald voor Sparkle.framework"
    success "  Sparkle.framework gesigned"
fi

# Stap 5: Sign Safari extensie app (van binnen naar buiten: eerst appex, dan app)
SAFARI_BUNDLED="$PLUGINS_DEST/FileFlower Safari.app"
SAFARI_APPEX="$SAFARI_BUNDLED/Contents/PlugIns/FileFlower Safari Extension.appex"

if [ -d "$SAFARI_APPEX" ]; then
    info "Signen van FileFlower Safari Extension.appex..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        --entitlements "$SAFARI_EXT_ENTITLEMENTS" \
        "$SAFARI_APPEX" \
        || error_exit "Code signing gefaald voor FileFlower Safari Extension.appex"
    success "  FileFlower Safari Extension.appex gesigned"
fi

if [ -d "$SAFARI_BUNDLED" ]; then
    info "Signen van FileFlower Safari.app..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        --entitlements "$SAFARI_APP_ENTITLEMENTS" \
        "$SAFARI_BUNDLED" \
        || error_exit "Code signing gefaald voor FileFlower Safari.app"
    success "  FileFlower Safari.app gesigned"

    # Verifieer Safari extensie signing chain
    info "Verifiëren Safari extensie signing..."
    codesign --verify --deep --strict "$SAFARI_BUNDLED" 2>&1 \
        || error_exit "Safari extensie signing verificatie gefaald"
    success "  Safari extensie signing geverifieerd"
fi

# Stap 6: Sign de Finder Sync Extension (met eigen entitlements, zonder get-task-allow)
if [ -d "$APPEX" ]; then
    info "Signen van FileFlowerFinderSync.appex..."
    codesign --force --sign "$SIGNING_IDENTITY" \
        --timestamp --options runtime \
        --entitlements "$FINDER_SYNC_ENTITLEMENTS" \
        "$APPEX" \
        || error_exit "Code signing gefaald voor FileFlowerFinderSync.appex"
    success "  FileFlowerFinderSync.appex gesigned"
fi

# Stap 7: Sign de hoofd-app (als laatste, met entitlements)
info "Signen van $APP_NAME.app..."
codesign --force --sign "$SIGNING_IDENTITY" \
    --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH" \
    || error_exit "Code signing gefaald voor $APP_NAME.app"
success "  $APP_NAME.app gesigned"

# Verifieer signature (deep check)
echo ""
info "Verifiëren van alle signatures..."
codesign --verify --deep --strict "$APP_PATH" 2>&1 \
    || error_exit "Code signing verificatie gefaald"
success "Alle signatures geverifieerd"

# Extra verificatie: Gatekeeper check
spctl --assess --type execute "$APP_PATH" 2>&1 \
    || warning "spctl assess waarschuwing (kan normaal zijn voor Sparkle)"

# Haal versie informatie op
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")

info "Versie: $VERSION (build $BUILD)"

# DMG bestandsnaam (zonder versienummer)
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# DMG aanmaken
echo ""
echo "💿 DMG aanmaken..."

# Verwijder oude DMG als die bestaat
rm -f "$DMG_PATH"

# Maak export directory
EXPORT_DIR="$BUILD_DIR/dmg_contents"
mkdir -p "$EXPORT_DIR"
ditto "$APP_PATH" "$EXPORT_DIR/$APP_NAME.app"

# Achtergrondafbeelding en volume-icoon
DMG_BACKGROUND_SRC="$PROJECT_ROOT/resources/dmg_background.png"
DMG_BACKGROUND="$BUILD_DIR/dmg_background.tiff"
VOLUME_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"

# Maak multi-resolution TIFF voor Retina support
if [ -f "$DMG_BACKGROUND_SRC" ]; then
    BG_1X="$BUILD_DIR/bg_1x.png"
    BG_2X="$BUILD_DIR/bg_2x.png"
    sips -z 400 600 "$DMG_BACKGROUND_SRC" --out "$BG_1X" > /dev/null 2>&1
    sips -z 800 1200 "$DMG_BACKGROUND_SRC" --out "$BG_2X" > /dev/null 2>&1
    tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$DMG_BACKGROUND" > /dev/null 2>&1
    rm -f "$BG_1X" "$BG_2X"
    success "Retina achtergrond TIFF aangemaakt (1x + 2x)"
else
    warning "Achtergrondafbeelding niet gevonden: $DMG_BACKGROUND_SRC"
    warning "DMG wordt zonder achtergrond aangemaakt"
fi

# Maak DMG met create-dmg
DMG_ARGS=(
    --volname "$APP_NAME"
    --window-pos 200 120
    --window-size 600 400
    --icon-size 120
    --icon "$APP_NAME.app" 155 255
    --hide-extension "$APP_NAME.app"
    --app-drop-link 445 255
)

# Voeg achtergrond toe als die bestaat
if [ -f "$DMG_BACKGROUND" ]; then
    DMG_ARGS+=(--background "$DMG_BACKGROUND")
fi

# Voeg volume-icoon toe als die bestaat
if [ -f "$VOLUME_ICON" ]; then
    DMG_ARGS+=(--volicon "$VOLUME_ICON")
fi

create-dmg \
    "${DMG_ARGS[@]}" \
    "$DMG_PATH" \
    "$EXPORT_DIR/" \
    || error_exit "DMG creatie gefaald"

success "DMG aangemaakt: $DMG_PATH"

# Cleanup
rm -rf "$EXPORT_DIR"
rm -rf "$SAFARI_BUILD_DIR"

# Notarisatie
echo ""
echo "📤 DMG indienen voor notarisatie bij Apple..."
info "Dit kan 2-5 minuten duren..."

# Submit en vang output op om status te checken
NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "FileFlower" \
    --wait 2>&1)
NOTARIZE_EXIT=$?

echo "$NOTARIZE_OUTPUT"

# Check exit code
if [ $NOTARIZE_EXIT -ne 0 ]; then
    error_exit "Notarisatie submit commando gefaald (exit code: $NOTARIZE_EXIT)"
fi

# Check of status "Accepted" is (notarytool kan exit 0 teruggeven bij Invalid)
if echo "$NOTARIZE_OUTPUT" | grep -q "status: Invalid"; then
    # Haal submission ID op voor log
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    echo ""
    warning "Notarisatie afgewezen! Log ophalen..."
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "FileFlower" 2>&1
    error_exit "Notarisatie afgewezen door Apple (status: Invalid). Zie log hierboven."
fi

if ! echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
    warning "Onverwachte notarisatie status. Output hierboven controleren."
    error_exit "Notarisatie niet bevestigd als 'Accepted'"
fi

success "Notarisatie goedgekeurd door Apple"

# Staple notarisatie ticket aan DMG
echo ""
echo "📎 Notarisatie ticket koppelen aan DMG..."
xcrun stapler staple "$DMG_PATH" \
    || error_exit "Stapling gefaald"
success "Notarisatie ticket gekoppeld"

# EdDSA signing voor Sparkle updates
echo ""
echo "🔑 DMG signen voor Sparkle updates..."
SPARKLE_SIGN_UPDATE="$BUILD_DIR/SourcePackages/checkouts/Sparkle/bin/sign_update"

if [ ! -f "$SPARKLE_SIGN_UPDATE" ]; then
    # Probeer alternatief pad (DerivedData)
    SPARKLE_SIGN_UPDATE=$(find "$BUILD_DIR" -name "sign_update" -path "*/Sparkle/*" 2>/dev/null | head -1)
fi

if [ -f "$SPARKLE_SIGN_UPDATE" ]; then
    SPARKLE_SIGNATURE=$("$SPARKLE_SIGN_UPDATE" "$DMG_PATH")
    success "DMG gesigned voor Sparkle"
    echo ""
    echo "📋 Sparkle signature info (voor appcast.xml):"
    echo "$SPARKLE_SIGNATURE"
    echo ""
else
    warning "sign_update tool niet gevonden. Sparkle EdDSA signing overgeslagen."
    warning "Voer handmatig uit: sparkle/bin/sign_update \"$DMG_PATH\""
fi

# Toon resultaat
echo ""
echo "========================================="
echo -e "${GREEN}   ✅ BUILD SUCCESVOL${NC}"
echo "========================================="
echo ""
echo "📍 Output:"
echo "   App: $APP_PATH"
echo "   DMG: $DMG_PATH"
echo ""

# Toon bestandsgrootte
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo "📊 Grootte:"
echo "   App: $APP_SIZE"
echo "   DMG: $DMG_SIZE"
echo ""

success "App is gesigned met Developer ID en genotariseerd door Apple."
echo "   Gebruikers kunnen de app direct openen zonder waarschuwingen."
echo ""

# Kopieer naar dist map
DIST_DIR="$PROJECT_ROOT/dist"
mkdir -p "$DIST_DIR"
cp "$DMG_PATH" "$DIST_DIR/"
success "DMG gekopieerd naar: $DIST_DIR/$(basename "$DMG_PATH")"
echo ""

# Genereer update info voor appcast
echo "📝 Update info voor appcast.xml:"
echo "   Versie: $VERSION"
echo "   Build: $BUILD"
echo "   Bestandsgrootte: $(stat -f%z "$DMG_PATH") bytes"
echo "   Bestandsnaam: $(basename "$DMG_PATH")"
echo ""

#!/bin/bash
# create_test_sdcard.sh
#
# Genereert een mountbare DMG die zich gedraagt als een Sony XAVC SD-kaart,
# voor handmatig testen van FileSafe features:
#   - Sony camera brand detectie via /PRIVATE/M4ROOT/CLIP/
#   - Multi-day shoot detectie (3 dagen spread)
#   - Ignored files/folders (THMBNL, XML sidecars, BIN, STATUS.BIN)
#   - Audio + foto's naast video (JPG + ARW RAW paren)
#
# Gebruik:
#   ./scripts/create_test_sdcard.sh              # maakt aan + mount
#   ./scripts/create_test_sdcard.sh --no-mount   # alleen DMG, niet mounten
#   ./scripts/create_test_sdcard.sh --eject      # bestaand volume unmounten
#
# DMG locatie: ~/Desktop/TEST_SDCARD_SONY.dmg

set -euo pipefail

VOLUME_NAME="TEST_SDCARD_SONY"
DMG_PATH="${HOME}/Desktop/${VOLUME_NAME}.dmg"
DMG_SIZE="200m"
MOUNT="/Volumes/${VOLUME_NAME}"

# --- Argumenten ---
NO_MOUNT=false
EJECT_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --no-mount) NO_MOUNT=true ;;
        --eject) EJECT_ONLY=true ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Onbekend argument: $arg"; exit 1 ;;
    esac
done

# --- Eject mode ---
if [ "$EJECT_ONLY" = true ]; then
    if [ -d "$MOUNT" ]; then
        echo "Unmounting $MOUNT..."
        hdiutil detach "$MOUNT" -force
        echo "✓ Unmounted."
    else
        echo "Niets gemount op $MOUNT."
    fi
    exit 0
fi

# --- Unmount existing before recreate ---
if [ -d "$MOUNT" ]; then
    echo "Bestaand volume gevonden op $MOUNT — unmounting..."
    hdiutil detach "$MOUNT" -force >/dev/null
fi

# --- Bestaande DMG afhandelen ---
if [ -f "$DMG_PATH" ]; then
    read -p "DMG bestaat al: $DMG_PATH — overschrijven? [y/N] " answer
    case "$answer" in
        y|Y) rm "$DMG_PATH" ;;
        *)   echo "Afgebroken."; exit 1 ;;
    esac
fi

# --- DMG aanmaken ---
echo "Aanmaken DMG ($DMG_SIZE, HFS+)..."
hdiutil create \
    -size "$DMG_SIZE" \
    -fs "HFS+" \
    -volname "$VOLUME_NAME" \
    -layout SPUD \
    "$DMG_PATH" >/dev/null

echo "Mounten..."
hdiutil attach "$DMG_PATH" >/dev/null

# --- Datums: 4, 3, 2 dagen geleden ---
DAY1=$(date -v-4d +%Y%m%d)
DAY2=$(date -v-3d +%Y%m%d)
DAY3=$(date -v-2d +%Y%m%d)

# mk_file <path> <size_kb> <YYYYMMDD> [HHMM]
mk_file() {
    local path="$1" size_kb="$2" day="$3" time="${4:-}"
    if [ -z "$time" ]; then
        # Random tijd tussen 09:00 en 17:59
        local h=$((9 + RANDOM % 9))
        local m=$((RANDOM % 60))
        time=$(printf "%02d%02d" "$h" "$m")
    fi
    local ts="${day}${time}"
    mkdir -p "$(dirname "$path")"
    dd if=/dev/urandom of="$path" bs=1024 count="$size_kb" status=none
    touch -t "$ts" "$path"
    # Creation date ook zetten (macOS)
    if command -v SetFile >/dev/null 2>&1; then
        local mm="${day:4:2}" dd_="${day:6:2}" yyyy="${day:0:4}"
        local hh="${time:0:2}" mi="${time:2:2}"
        SetFile -d "${mm}/${dd_}/${yyyy} ${hh}:${mi}:00" "$path" 2>/dev/null || true
    fi
}

echo "Populating Sony SD card structuur..."

# =============================================================
# VIDEO — Sony XAVC clips in PRIVATE/M4ROOT/CLIP/
# =============================================================

# Dag 1 — MXF clips (ochtend + middag)
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0001.MXF"       2560 "$DAY1" "0930"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0001M01.XML"       4 "$DAY1" "0930"  # ignored sidecar
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0002.MXF"       1800 "$DAY1" "1015"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0002M01.XML"       4 "$DAY1" "1015"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0003.MXF"       3200 "$DAY1" "1420"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0003M01.XML"       4 "$DAY1" "1420"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0004.MXF"       2048 "$DAY1" "1555"

# Dag 2
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0005.MXF"       4096 "$DAY2" "1005"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0006.MXF"       2816 "$DAY2" "1138"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0007.MXF"       3072 "$DAY2" "1345"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0008.MXF"       2304 "$DAY2" "1520"

# Dag 3 — gemengd MP4 (XAVC-S) + MXF
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0009.MP4"       1536 "$DAY3" "0915"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0010.MP4"       2048 "$DAY3" "1102"
mk_file "$MOUNT/PRIVATE/M4ROOT/CLIP/C0011.MXF"       1792 "$DAY3" "1430"

# --- Sony systeem mappen/bestanden (moeten GENEGEERD worden) ---
mk_file "$MOUNT/PRIVATE/M4ROOT/THMBNL/C0001T01.JPG"    48 "$DAY1" "0930"  # ignored folder
mk_file "$MOUNT/PRIVATE/M4ROOT/THMBNL/C0005T01.JPG"    48 "$DAY2" "1005"
mk_file "$MOUNT/PRIVATE/M4ROOT/GENERAL/PANA_GRP/INDEX.XML"  8 "$DAY1"    # ignored ext
mk_file "$MOUNT/PRIVATE/M4ROOT/MEDIAPRO.XML"            4 "$DAY1"          # ignored ext
mk_file "$MOUNT/AVF_INFO/AVIN0001.BIN"                  2 "$DAY1"          # ignored ext

# =============================================================
# AUDIO — Externe recorder (Zoom H5 stijl)
# =============================================================

mk_file "$MOUNT/AUDIO/ZOOM0001.WAV"  1024 "$DAY1" "0900"
mk_file "$MOUNT/AUDIO/ZOOM0002.WAV"   768 "$DAY1" "1400"
mk_file "$MOUNT/AUDIO/ZOOM0003.WAV"  1536 "$DAY2" "0950"
mk_file "$MOUNT/AUDIO/ZOOM0004.WAV"   512 "$DAY2" "1600"
mk_file "$MOUNT/AUDIO/ZOOM0005.WAV"   896 "$DAY3" "1015"

# =============================================================
# FOTO'S — Sony stills in DCIM/100MSDCF/
# =============================================================

# Dag 1 — JPG + ARW paren (test RAW/JPEG split)
mk_file "$MOUNT/DCIM/100MSDCF/DSC00001.JPG"   640 "$DAY1" "1050"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00001.ARW"  2048 "$DAY1" "1050"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00002.JPG"   512 "$DAY1" "1053"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00002.ARW"  2048 "$DAY1" "1053"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00003.JPG"   720 "$DAY1" "1455"

# Dag 2 — alleen JPG
mk_file "$MOUNT/DCIM/100MSDCF/DSC00004.JPG"   688 "$DAY2" "1210"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00005.JPG"   592 "$DAY2" "1212"

# Dag 3 — alleen RAW
mk_file "$MOUNT/DCIM/100MSDCF/DSC00006.ARW"  2304 "$DAY3" "1005"
mk_file "$MOUNT/DCIM/100MSDCF/DSC00007.ARW"  1920 "$DAY3" "1530"

# --- Finderbestanden aan root (worden genegeerd) ---
touch "$MOUNT/.DS_Store" 2>/dev/null || true

echo ""
echo "✓ Test SD-kaart gemount op: $MOUNT"
echo "✓ DMG opgeslagen: $DMG_PATH"
echo ""
echo "Inhoud:"
echo "  • Camera   : Sony (detectie via /PRIVATE/M4ROOT/CLIP/)"
echo "  • Video    : 13 clips (11 MXF + 2 MP4)"
echo "  • Audio    : 5 WAV files"
echo "  • Foto's   : 9 stills (5 JPG + 4 ARW — 2 paren voor RAW/JPEG split)"
echo "  • Dagen    : $DAY1, $DAY2, $DAY3"
echo ""
echo "Test scenarios (wat FileSafe moet doen):"
echo "  ✓ Camera brand detectie → 'Sony'"
echo "  ✓ Multi-day detectie → 3 kalenderdagen"
echo "  ✓ THMBNL map negeren (2 JPG thumbs)"
echo "  ✓ XML sidecars negeren (13 totaal)"
echo "  ✓ BIN systeembestand negeren (AVIN0001.BIN)"
echo "  ✓ RAW/JPEG split optie herkent 2 paren op dag 1"
echo ""
echo "Test de app:"
echo "  1. Start FileFlower"
echo "  2. Open FileSafe → kies volume '$VOLUME_NAME'"
echo ""
echo "Unmount later:"
echo "  ./scripts/create_test_sdcard.sh --eject"
echo "Of handmatig:  hdiutil detach \"$MOUNT\""

if [ "$NO_MOUNT" = true ]; then
    echo ""
    echo "--no-mount opgegeven — unmounting..."
    hdiutil detach "$MOUNT" -force >/dev/null
    echo "✓ Unmounted. Mount later met: hdiutil attach \"$DMG_PATH\""
fi

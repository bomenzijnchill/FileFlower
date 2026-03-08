#!/bin/bash

# Script om de FileFlower server status te controleren

PORT=17890
URL="http://127.0.0.1:$PORT/jobs/next"

echo "=== FileFlower Server Status ==="
echo ""

# Check if process is listening on port
if lsof -i :$PORT 2>/dev/null | grep -q LISTEN; then
    PROCESS=$(lsof -i :$PORT 2>/dev/null | grep LISTEN | awk '{print $2}')
    echo "✓ Server draait (proces ID: $PROCESS)"
    echo ""
    
    # Test HTTP connection
    echo "Testen HTTP verbinding..."
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$URL" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ HTTP verbinding OK (status: $HTTP_CODE)"
        if [ "$BODY" = "{}" ]; then
            echo "✓ Geen jobs in wachtrij"
        else
            echo "⚠ Jobs beschikbaar: $BODY"
        fi
    else
        echo "✗ HTTP verbinding gefaald (status: $HTTP_CODE)"
    fi
else
    echo "✗ Server draait NIET"
    echo ""
    echo "Start de macOS app om de server te starten."
fi

echo ""
echo "=== Plugin Status ==="
PLUGIN_DIR="$HOME/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge"
SOURCE_FILE="PremierePlugin_CEP/index.js"

if [ -f "$PLUGIN_DIR/index.js" ]; then
    if [ -f "$SOURCE_FILE" ]; then
        if diff -q "$PLUGIN_DIR/index.js" "$SOURCE_FILE" >/dev/null 2>&1; then
            echo "✓ Plugin is up-to-date"
        else
            echo "⚠ Plugin is NIET up-to-date"
            echo "  Run: bash update_plugin.sh"
        fi
    else
        echo "⚠ Bronbestand niet gevonden: $SOURCE_FILE"
    fi
else
    echo "✗ Plugin niet geïnstalleerd in: $PLUGIN_DIR"
fi









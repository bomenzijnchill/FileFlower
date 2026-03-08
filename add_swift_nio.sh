#!/bin/bash

# Script om SwiftNIO toe te voegen aan Xcode project
# Dit script voegt de package dependency toe aan het project.pbxproj bestand

PROJECT_FILE="FileFlower/FileFlower.xcodeproj/project.pbxproj"

echo "⚠️  Dit script werkt alleen als Xcode gesloten is!"
echo "⚠️  Het is beter om de dependency handmatig toe te voegen via Xcode UI"
echo ""
echo "Om handmatig toe te voegen:"
echo "1. Open FileFlower.xcodeproj in Xcode"
echo "2. Selecteer het project in de navigator"
echo "3. Selecteer het target 'FileFlower'"
echo "4. Ga naar 'Package Dependencies' tab"
echo "5. Klik op '+' en voeg toe: https://github.com/apple/swift-nio.git"
echo "6. Selecteer NIO en NIOHTTP1 modules"
echo ""
echo "Of gebruik dit commando in Xcode (met project open):"
echo "xcodebuild -resolvePackageDependencies -project FileFlower.xcodeproj"

# Fix Dependencies - Stap voor Stap

## Probleem 1: SwiftNIO niet gevonden in Xcode

### Oplossing via Xcode UI:

1. **Open het Xcode project**
   - Open `FileFlower_V2.xcodeproj` in Xcode

2. **Voeg Swift Package Dependency toe**
   - Selecteer het project in de navigator (bovenaan links)
   - Selecteer het target "FileFlower_V2"
   - Ga naar het tabblad **"Package Dependencies"**
   - Klik op de **"+"** knop
   - Voer in: `https://github.com/apple/swift-nio.git`
   - Kies versie: **"Up to Next Major Version"** met `2.60.0`
   - Klik **"Add Package"**
   - Selecteer de volgende producten:
     - ✅ **NIO**
     - ✅ **NIOHTTP1**
   - Klik **"Add Package"**

3. **Verifieer**
   - Build het project (Cmd+B)
   - De foutmeldingen zouden nu weg moeten zijn

### Alternatief: Via Terminal (als Xcode UI niet werkt)

```bash
cd /Users/koendijkstra/FileFlower_V2/FileFlower_V2
xcodebuild -resolvePackageDependencies
```

## Probleem 2: UXP "App not supported"

### Mogelijke oorzaken en oplossingen:

1. **Check manifest.json structuur**
   - Zorg dat `manifest.json` geldig JSON is
   - Verifieer dat alle verplichte velden aanwezig zijn

2. **Check UXP Developer Tools versie**
   - Zorg dat je de nieuwste versie hebt
   - Download van: https://developer.adobe.com/uxp/uxp-developer-tools/

3. **Check Premiere Pro versie**
   - Plugin vereist Premiere Pro 23.0.0 of hoger
   - Verifieer je Premiere Pro versie

4. **Probeer alternatieve manifest structuur**
   - Zie de bijgewerkte manifest.json hieronder

5. **Check console logs**
   - Open UXP Developer Tools
   - Kijk naar de console voor specifieke foutmeldingen

### Debug stappen:

1. Valideer JSON:
```bash
cd PremierePlugin
python3 -m json.tool manifest.json
```

2. Test met minimale manifest:
   - Probeer eerst met alleen de basisvelden
   - Voeg geleidelijk meer toe

3. Check UXP Developer Tools logs:
   - Window > Developer Tools > Console
   - Zoek naar specifieke foutmeldingen


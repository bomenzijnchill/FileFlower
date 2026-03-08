# Build Instructies

## macOS App

### Vereisten
- Xcode 15+ 
- macOS Sonoma/Sequoia
- Swift 5.9+

### Stappen

1. **Maak Xcode Project**
   ```bash
   cd MacApp
   # Maak een nieuw Xcode project:
   # - File > New > Project
   # - macOS > App
   # - Language: Swift
   # - UI: SwiftUI
   # - Name: FileFlower
   ```

2. **Voeg SwiftNIO toe**
   - In Xcode: File > Add Package Dependencies
   - URL: `https://github.com/apple/swift-nio.git`
   - Version: 2.60.0 of hoger
   - Selecteer: NIO, NIOHTTP1

3. **Voeg bestanden toe aan project**
   - Sleep alle bestanden uit de MacApp folder naar het Xcode project
   - Zorg dat Resources (mood_list.json, genre_list.json) in de app bundle komen

4. **Configureer Capabilities**
   - Selecteer het target
   - Ga naar Signing & Capabilities
   - Schakel App Sandbox UIT (of configureer de benodigde permissions)
   - Voeg "Outgoing Connections" toe indien nodig

5. **Build & Run**
   - Selecteer een Apple Silicon Mac als destination
   - Cmd+R om te builden en runnen

### Permissions

Na eerste run:
- System Settings > Privacy & Security > Full Disk Access
- Voeg de app toe en geef toegang

## Premiere Plugin

### Vereisten
- Adobe Premiere Pro 23.0.0+
- UXP Developer Tools (voor development)

### Installatie

1. **Development mode:**
   ```bash
   # Installeer UXP Developer Tools van Adobe
   # Open UXP Developer Tools
   # File > Load Extension > Selecteer PremierePlugin folder
   ```

2. **Production installatie:**
   ```bash
   # Kopieer PremierePlugin folder naar:
   ~/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge
   ```

3. **Start Premiere Pro**
   - Window > Extensions > FileFlower Bridge

### Troubleshooting

- Zorg dat de macOS app draait en de HTTP server actief is
- Check console logs in Premiere Pro voor errors
- Verifieer dat CSInterface beschikbaar is in de UXP runtime

## Testing

1. Start de macOS app
2. Voeg een project root toe in instellingen
3. Download een test bestand naar ~/Downloads
4. App zou het moeten detecteren
5. Kies project en type
6. Bevestig → bestand wordt verplaatst
7. Premiere plugin zou het moeten importeren

## Notes

- De app gebruikt FSEvents voor file watching (vereist toegang tot Downloads)
- HTTP server draait op localhost:17890
- Config wordt opgeslagen in ~/Library/Application Support/FileFlower/


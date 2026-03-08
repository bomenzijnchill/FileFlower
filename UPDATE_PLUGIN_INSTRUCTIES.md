# Plugin Update Instructies

## Locatie van geïnstalleerde plugin:
```
~/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge/
```

## Bestanden die vervangen moeten worden:

### 1. index.js (belangrijkste bestand)
**Bron:** `PremierePlugin_CEP/index.js`  
**Doel:** `~/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge/index.js`

### 2. jsx/bridge.jsx (optioneel, maar aanbevolen)
**Bron:** `PremierePlugin_CEP/jsx/bridge.jsx`  
**Doel:** `~/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge/jsx/bridge.jsx`

## Update Methoden:

### Methode 1: Via Terminal (snelste manier)
```bash
# Ga naar de project directory
cd /Users/koendijkstra/FileFlower_V2

# Update index.js
sudo cp PremierePlugin_CEP/index.js ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/index.js

# Update bridge.jsx (optioneel)
sudo cp PremierePlugin_CEP/jsx/bridge.jsx ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/jsx/bridge.jsx
```

### Methode 2: Handmatig via Finder
1. Open Finder
2. Druk op `Cmd+Shift+G` (Ga naar map)
3. Typ: `~/Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge`
4. Vervang `index.js` met het bestand uit `PremierePlugin_CEP/index.js`
5. (Optioneel) Vervang `jsx/bridge.jsx` met het bestand uit `PremierePlugin_CEP/jsx/bridge.jsx`

### Methode 3: Via het update script
```bash
cd /Users/koendijkstra/FileFlower_V2
./update_plugin.sh
```

**Let op:** Als je een "Permission denied" fout krijgt, gebruik dan `sudo` voor de cp commando's.

## Na het updaten:

1. **Sluit Premiere Pro volledig af** (niet alleen het venster, maar helemaal afsluiten)
2. **Herstart Premiere Pro**
3. **Open het plugin panel opnieuw** (Window > Extensions > FileFlower Bridge)
4. **Test de functionaliteit**

## Verificatie:

Na het updaten zou je in de log moeten zien:
- "Controleren project:" in plaats van "Project openen:"
- Geen "Illegal Parameter type" errors meer
- Bestanden worden geïmporteerd in bestaande bins met muziek/audio namen









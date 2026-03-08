# Premiere Plugin Installatie - Stap voor Stap

## Xcode Fouten ✅ OPGELOST

De Xcode compileerfouten zijn opgelost:
- ✅ JobServer ByteBuffer problemen gefixed
- ✅ ProjectInfo Hashable conformance toegevoegd

## Plugin Installatie

De plugin is nog niet geïnstalleerd. Volg deze stappen:

### Optie 1: Automatisch (aanbevolen)

Open Terminal en voer uit:

```bash
cd /Users/koendijkstra/FileFlower_V2
sudo bash INSTALL_PLUGIN_NU.sh
```

Je wordt gevraagd om je wachtwoord.

### Optie 2: Handmatig

```bash
# 1. Kopieer plugin
sudo cp -r /Users/koendijkstra/FileFlower_V2/PremierePlugin_CEP \
   ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge

# 2. Kopieer CSInterface.js
cp /Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js \
   ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/CSInterface.js

# 3. Fix permissions
sudo chown -R $(whoami):staff ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
chmod -R 755 ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
```

### Verificatie

```bash
# Check of plugin geïnstalleerd is
ls -la ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/

# Je zou moeten zien:
# - CSXS/manifest.xml ✅
# - CSInterface.js ✅
# - index.html ✅
# - index.js ✅
# - jsx/bridge.jsx ✅
```

### Na Installatie

1. **Herstart Premiere Pro volledig** (niet alleen sluiten, maar quit)
2. Start Premiere Pro opnieuw
3. Ga naar: **Window > Extensions > FileFlower Bridge**
4. De plugin zou moeten verschijnen

### Als Plugin Niet Verschijnt

1. **Check CEP logging:**
   ```bash
   defaults write com.adobe.CSXS.Player LogLevel 5
   defaults write com.adobe.CSXS.10 LogLevel 5
   ```

2. **Check logs:**
   ```bash
   tail -f ~/Library/Logs/Adobe/CEP/*.log
   ```

3. **Verifieer manifest:**
   ```bash
   cat ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/CSXS/manifest.xml
   ```

4. **Check Premiere Pro versie:**
   - Plugin vereist Premiere Pro 23.0.0 of hoger
   - Check: Premiere Pro > About Premiere Pro

### Troubleshooting

- **"App not supported"**: Gebruik CEP versie (PremierePlugin_CEP), niet UXP versie
- **Plugin verschijnt niet**: Herstart Premiere Pro volledig, check logs
- **Geen verbinding**: Zorg dat macOS app draait en HTTP server actief is op localhost:17890


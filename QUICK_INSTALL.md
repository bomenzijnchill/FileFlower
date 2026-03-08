# Snelle Plugin Installatie

## Xcode Fouten ✅ OPGELOST

De ByteBuffer API is gecorrigeerd. De code zou nu moeten compileren.

## Plugin Installeren

**Voer dit uit in Terminal:**

```bash
cd /Users/koendijkstra/FileFlower_V2
sudo bash INSTALL_PLUGIN_NU.sh
```

**Of handmatig:**

```bash
# 1. Kopieer plugin
sudo cp -r PremierePlugin_CEP ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge

# 2. Kopieer CSInterface.js
cp /Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js \
   ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/CSInterface.js

# 3. Fix permissions
sudo chown -R $(whoami):staff ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
```

## Na Installatie

1. **Herstart Premiere Pro volledig** (Quit, niet alleen sluiten)
2. Start Premiere Pro opnieuw  
3. Ga naar: **Window > Extensions > FileFlower Bridge**

## Als Plugin Niet Verschijnt

1. Check of geïnstalleerd:
   ```bash
   ls -la ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/
   ```

2. Enable CEP logging:
   ```bash
   defaults write com.adobe.CSXS.Player LogLevel 5
   defaults write com.adobe.CSXS.10 LogLevel 5
   ```

3. Check logs:
   ```bash
   tail -f ~/Library/Logs/Adobe/CEP/*.log
   ```

4. Verifieer Premiere Pro versie (moet 23.0.0+ zijn)


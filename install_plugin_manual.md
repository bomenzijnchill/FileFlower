# Handmatige Plugin Installatie

Het automatische install script heeft permission problemen. Volg deze stappen handmatig:

## Stap 1: Open Terminal

## Stap 2: Kopieer de plugin

```bash
# Ga naar het project directory
cd /Users/koendijkstra/FileFlower_V2

# Kopieer de plugin (gebruik sudo als nodig)
sudo cp -r PremierePlugin_CEP ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge

# Fix permissions
sudo chown -R $(whoami):staff ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
```

## Stap 3: Kopieer CSInterface.js

```bash
# Kopieer CSInterface.js van je oude plugin
cp /Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js \
   ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/CSInterface.js
```

## Stap 4: Verifieer

```bash
# Check of alles er is
ls -la ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/

# Je zou moeten zien:
# - CSXS/manifest.xml
# - CSInterface.js
# - index.html
# - index.js
# - jsx/bridge.jsx
```

## Stap 5: Herstart Premiere Pro

1. Sluit Premiere Pro volledig af
2. Start Premiere Pro opnieuw
3. Ga naar: **Window > Extensions > FileFlower Bridge**

## Troubleshooting

Als de plugin niet verschijnt:

1. **Check CEP logging:**
   ```bash
   defaults write com.adobe.CSXS.Player LogLevel 5
   defaults write com.adobe.CSXS.10 LogLevel 5
   ```

2. **Check logs:**
   ```bash
   tail -f ~/Library/Logs/Adobe/CEP/*.log
   ```

3. **Verifieer manifest.xml:**
   ```bash
   cat ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge/CSXS/manifest.xml
   ```


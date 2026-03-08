# CEP Plugin Setup Instructies

## Waarom CEP in plaats van UXP?

Je oude plugin gebruikt CEP (Common Extensibility Platform), wat stabieler en bewezen werkt met Premiere Pro. UXP is nieuwer maar kan compatibiliteitsproblemen hebben.

## Installatie Stappen

### 1. Kopieer CSInterface.js

De CSInterface.js moet gekopieerd worden van je oude plugin:

```bash
cp /Users/koendijkstra/FileFlower/FileFlower/FileFlowerCEP/CSInterface.js \
   /Users/koendijkstra/FileFlower_V2/PremierePlugin_CEP/CSInterface.js
```

### 2. Installeer CEP Plugin

```bash
# Maak CEP extensions directory aan als die niet bestaat
mkdir -p ~/Library/Application\ Support/Adobe/CEP/extensions

# Kopieer plugin
cp -r PremierePlugin_CEP ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
```

### 3. Enable CEP Debugging (optioneel)

```bash
# Enable CEP logging
defaults write com.adobe.CSXS.Player LogLevel 5
defaults write com.adobe.CSXS.10 LogLevel 5

# Herstart Premiere Pro
```

### 4. Test de Plugin

1. Start de macOS app (zorg dat HTTP server draait)
2. Start Premiere Pro
3. Ga naar: Window > Extensions > FileFlower Bridge
4. De plugin zou moeten verbinden en wachten op jobs

## Troubleshooting

- **Plugin verschijnt niet in menu:**
  - Check dat de manifest.xml correct is
  - Verifieer dat CSInterface.js aanwezig is
  - Check CEP logs: `~/Library/Logs/Adobe/CEP/`

- **"App not supported" fout:**
  - CEP gebruikt manifest.xml, niet manifest.json
  - Zorg dat je PremierePlugin_CEP gebruikt, niet PremierePlugin

- **Geen verbinding met macOS app:**
  - Check dat de macOS app draait
  - Test HTTP endpoint: `curl http://127.0.0.1:17890/jobs/next`
  - Check firewall instellingen

## Structuur

```
PremierePlugin_CEP/
├── CSXS/
│   └── manifest.xml      # CEP manifest (niet JSON!)
├── jsx/
│   └── bridge.jsx        # ExtendScript code
├── CSInterface.js         # Adobe CEP library (kopieer van oude plugin)
├── index.html            # UI
└── index.js              # Main JavaScript
```


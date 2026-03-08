# FileFlower

Slimme downloader die automatisch assets naar projectmappen verplaatst en importeert in Adobe Premiere Pro.

## Overzicht

FileFlower bestaat uit drie componenten:

1. **macOS Menubar App** (Swift/SwiftUI) - Monitort Downloads, classificeert assets, verplaatst bestanden
2. **Premiere UXP Plugin** - Importeert bestanden automatisch in Premiere Pro

## Vereisten

- macOS Sonoma/Sequoia (Apple Silicon)
- Adobe Premiere Pro 23.0.0 of hoger
- Xcode 15+ voor development
- SwiftNIO voor HTTP server functionaliteit

## Installatie

### macOS App

1. Open het project in Xcode
2. Configureer signing & capabilities
3. Build en run
4. Geef Full Disk Access in System Settings > Privacy & Security

### Premiere Plugin

1. Kopieer `PremierePlugin` naar `~/Library/Application Support/Adobe/CEP/extensions/`
2. Of gebruik UXP Developer Tools voor development

## Eerste Setup

1. Start de app
2. Open Instellingen en voeg project roots toe
3. Kies Music classificatie mode (Mood of Genre)
4. Optioneel: link Finder mappen aan Premiere bins

## Workflow

1. Download asset → App detecteert automatisch
2. Kies project (top 3 recent)
3. Kies type (Music/SFX/VO/etc) en subfolder
4. Bevestig → Bestand wordt verplaatst en geïmporteerd in Premiere

## Project Structuur

```
FileFlower/
├── FileFlower/
│   ├── FileFlowerApp.swift
│   ├── Models/
│   ├── Services/
│   ├── UI/
│   ├── Utils/
│   └── Resources/
└── PremierePlugin/
    ├── manifest.json
    ├── index.html
    ├── index.js
    └── jsx/
```

## Development

### macOS App

```bash
cd MacApp
# Open in Xcode of gebruik Swift Package Manager
```

### Premiere Plugin

Gebruik UXP Developer Tools om de plugin te testen tijdens development.

## Configuratie

Config wordt opgeslagen in:
`~/Library/Application Support/FileFlower/config.json`

## Licentie

Privé project


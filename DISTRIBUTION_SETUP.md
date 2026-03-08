# FileFlower Distributie Setup

Dit document beschrijft hoe je FileFlower kunt bouwen en distribueren via Gumroad met GitHub releases.

## Overzicht

```
Distributie Flow:
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Build DMG     │ ──▶ │  Upload naar    │ ──▶ │  Verkoop via    │
│   (lokaal)      │     │  GitHub Release │     │  Gumroad        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                │
                                ▼
                        ┌─────────────────┐
                        │  appcast.xml    │
                        │  voor updates   │
                        └─────────────────┘
```

## Vereisten

### Software
- macOS 13.0 of hoger
- Xcode 15.0 of hoger
- `create-dmg`: `brew install create-dmg`
- GitHub CLI: `brew install gh`

### Accounts
- GitHub account (gratis)
- Gumroad account (gratis, 10% per verkoop)

## Stap 1: Gumroad Setup

### 1.1 Product Aanmaken
1. Ga naar [gumroad.com](https://gumroad.com) en maak een account
2. Klik op **New Product**
3. Kies **Digital Product**
4. Vul in:
   - Naam: "FileFlower"
   - Prijs: jouw gekozen prijs
   - Beschrijving: wat de app doet

### 1.2 Product ID Ophalen
1. Ga naar je product settings
2. Zoek de **Product ID** (bijv. `abcde`)
3. Kopieer deze

### 1.3 License Key Instellen in Code
Open `LicenseManager.swift` en pas aan:

```swift
private let productId = "JOUW_GUMROAD_PRODUCT_ID"
```

### 1.4 Purchase Link Instellen
Open `LicenseView.swift` en pas de URL aan:

```swift
if let url = URL(string: "https://jouwaccount.gumroad.com/l/PRODUCT_ID") {
```

## Stap 2: GitHub Repository Setup

### 2.1 Maak een Public Repository
1. Ga naar [github.com/new](https://github.com/new)
2. Naam: `fileflower-releases`
3. Zet op **Public** (nodig voor downloads)
4. Maak de repo aan

### 2.2 Clone en Setup
```bash
git clone https://github.com/JOUW_USERNAME/fileflower-releases.git
cd fileflower-releases

# Kopieer appcast.xml
cp /path/to/FileFlower_V2/examples/appcast.xml .

# Pas de URLs aan in appcast.xml
# Vervang YOUR_USERNAME met je GitHub username

git add appcast.xml
git commit -m "Initial appcast"
git push
```

### 2.3 GitHub CLI Authenticatie
```bash
gh auth login
# Kies: GitHub.com → HTTPS → Login with browser
```

### 2.4 Update Script Configuratie
Open `scripts/create_release.sh` en pas aan:

```bash
GITHUB_REPO="JOUW_USERNAME/fileflower-releases"
```

## Stap 3: Update URL in Code

Open `UpdateManager.swift` en pas aan:

```swift
static let appcastURL = "https://raw.githubusercontent.com/JOUW_USERNAME/fileflower-releases/main/appcast.xml"
```

## Stap 4: Eerste Release Bouwen

### 4.1 Bundle Plugins
```bash
cd /Users/koendijkstra/FileFlower_V2
./scripts/bundle_plugins.sh
```

### 4.2 Build DMG
```bash
./scripts/build_dmg.sh
```

Dit maakt een DMG in de `dist/` folder.

### 4.3 Upload naar GitHub
```bash
./scripts/create_release.sh
```

Volg de prompts:
1. Bevestig de versie
2. Voer release notes in
3. Bevestig de upload

### 4.4 Update appcast.xml
Het script toont de XML die je moet toevoegen aan `appcast.xml`:

```bash
cd ~/path/to/fileflower-releases
# Voeg de nieuwe <item> toe aan appcast.xml
git add appcast.xml
git commit -m "Release v1.0.0"
git push
```

### 4.5 Upload DMG naar Gumroad
1. Ga naar je product op Gumroad
2. Upload de DMG als "Content"
3. Publiceer het product

## Gebruikers Flow

1. Klant koopt op Gumroad → krijgt license key
2. Klant download DMG van Gumroad (of GitHub)
3. Installeert app (rechts-klik → Open → Open)
4. Voert license key in
5. App is geactiveerd!

## Updates Uitbrengen

### Checklist voor elke update

1. **Versie verhogen** in Xcode:
   - Target → General → Version (bijv. 1.1.0)
   - Target → General → Build (bijv. 2)

2. **Plugin versies verhogen** (indien gewijzigd):
   - `PremierePlugin_CEP/CSXS/manifest.xml`
   - `ChromeExtension/manifest.json`

3. **Build & Release**:
   ```bash
   ./scripts/bundle_plugins.sh
   ./scripts/build_dmg.sh
   ./scripts/create_release.sh
   ```

4. **Update appcast.xml** en push naar GitHub

5. **Update Gumroad** product met nieuwe DMG (optioneel)

## Trial Periode

De app heeft een ingebouwde trial van 7 dagen. Pas dit aan in `LicenseManager.swift`:

```swift
/// Aantal dagen voor trial periode (0 = geen trial)
private let trialDays = 7
```

## Troubleshooting

### "App kan niet worden geopend"
Dit is normaal zonder Apple Developer account. Gebruikers moeten:
1. Rechts-klikken op de app
2. Kies "Open"
3. Klik "Open" in de dialog

### License validatie werkt niet
1. Check je Gumroad Product ID
2. Test de license key op Gumroad's site
3. Check je internetverbinding

### Updates worden niet gevonden
1. Verifieer de appcast.xml URL
2. Check of de URL publiek toegankelijk is
3. Controleer het versienummer in de appcast

## Bestandsstructuur

```
fileflower-releases/          # Public GitHub repo
├── appcast.xml                 # Update manifest
└── (releases worden automatisch
     door GitHub beheerd)

FileFlower_V2/                # Je development repo (privé)
├── dist/                       # Gebouwde DMGs
├── scripts/
│   ├── build_dmg.sh           # Bouwt de DMG
│   ├── bundle_plugins.sh      # Bundelt plugins
│   └── create_release.sh      # Maakt GitHub release
└── ...
```

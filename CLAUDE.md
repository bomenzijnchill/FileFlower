# CLAUDE.md

Werkafspraken voor het werken in deze repo. Lees dit vóór je code wijzigt of commit.

## Randvoorwaarden

- **Deze repo is publiek** — `github.com/bomenzijnchill/FileFlower`. Alles wat je commit is voor
  iedereen leesbaar, ook na een revert (het blijft in de git-historie staan). Behandel elke commit
  als een publicatie. Dat geldt ook voor **commit-berichten**: beschrijf daarin nooit een
  kwetsbaarheid die nog niet is uitgerold. Schrijf wát je gewijzigd hebt, niet wat er kapot was.
  Dit bestand valt onder dezelfde regel — zet er geen openstaande beveiligingsgaten in.
- **Er is geen test-target en geen CI.** Geen `.github/workflows`, geen XCTest-bundle. Niets vangt
  een fout op nadat je gecommit hebt. De compiler is het enige vangnet dat je hebt — daarom is de
  build-check hieronder verplicht en niet optioneel.
- **Nederlands** voor commit messages, code-commentaar en docs. UI-strings zijn Engels (bron-taal)
  en worden vertaald via `Localizable.xcstrings`.
- **Niet committen zonder dat de gebruiker erom vraagt.** Zeker niet pushen of releasen.

## Vóór elke commit

### 1. Build-check (verplicht)

```bash
cd FileFlower && xcodebuild -project FileFlower.xcodeproj -scheme FileFlower -configuration Debug -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Duurt ~1–3 minuten, geen signing of notarisatie nodig. Het scheme `FileFlower` bouwt zowel de app
als het `FileFlowerFinderSync`-target. **Geen `BUILD SUCCEEDED` = niet committen.**

Let op twee valkuilen bij het lezen van de output:

- Een **compiler-crash** geeft géén regel die met `error:` begint. Zoek op `Stack dump`,
  `Failed frontend command` en `BUILD FAILED` — niet alleen op `error:`.
- **Warnings zijn geen groen licht.** Alleen `BUILD SUCCEEDED` telt.

Raak je alleen niet-Swift-code aan, doe dan de bijpassende check in plaats van (of naast) de build:

| Wat je wijzigde | Check |
| --- | --- |
| `ChromeExtension/`, `PremierePlugin_CEP/`, `cloudflare-proxy/src/` | `node --check <bestand>` op elke gewijzigde `.js` |
| `manifest.json`, `*.xcstrings`, `Contents.json` | `python3 -m json.tool <bestand> > /dev/null` |
| `ResolvePlugin/fileflower_resolve_bridge.py`, `scripts/*.py` | `python3 -m py_compile <bestand>` |
| `PremierePlugin_CEP/CSXS/manifest.xml`, `appcast.xml` | `xmllint --noout <bestand>` |

### 2. Security-check (verplicht)

Draai `/security-review` bij alles wat het netwerk, het bestandssysteem, de licentie of de
integraties raakt. Loop daarnaast deze lijst langs — dit zijn de plekken waar het in deze repo
eerder mis is gegaan of mis kán gaan:

**Secrets**

- Geen secrets in de commit: `git diff --cached | grep -nEi 'sk-ant-|service_role|password|secret|BEGIN .*PRIVATE KEY'`
- De Claude API-key van de gebruiker hoort in de **Keychain** (`com.fileflower.claude-api-key`,
  zie `ClaudeClassificationStrategy.swift`) — nooit in `config.json`, nooit in een log, nooit in
  een analytics-event.
- De **Supabase anon-key staat bewust hardcoded** in `FileFlower/FileFlower/Services/SupabaseClient.swift`.
  Dat is geen lek: die key is publiek bedoeld en de RLS staat op INSERT-only voor de anon-rol.
  De `service_role`-key mag hier **nooit** terechtkomen.
- Cloudflare-proxy secrets (`ANTHROPIC_API_KEY`, `RESEND_API_KEY`) gaan via `wrangler secret put`,
  nooit in `wrangler.toml` of `wrangler.jsonc`.

**Cloudflare-proxy (`cloudflare-proxy/src/index.js`)**

De worker staat vóór betaalde API-keys (Anthropic, Resend); misbruik kost direct geld.
Let op: **code in de repo is niet automatisch live** — een wijziging telt pas na `wrangler deploy`.
Een gecommitte fix die niet gedeployed is, is geen fix. Raadpleeg de lokale (gitignorede)
auditrapporten in de projectmap voordat je hieraan werkt.

**Lokale HTTP-server (`JobServer.swift`, poort 17890)**

Deze server draait op de machine van de gebruiker en is bereikbaar vanuit elke webpagina die de
gebruiker open heeft. Twee beschermingen zijn er expliciet ingebouwd; sloop ze niet en omzeil ze
niet bij nieuwe endpoints:

- `isLoopbackHost(_:)` — weigert requests met een niet-loopback `Host`-header (DNS-rebinding).
- `isDisallowedWebOrigin(_:)` — weigert state-muterende requests met een web-`Origin` (CSRF).
  De plugins en de Python-bridge sturen géén `Origin`; een willekeurige webpagina wel.

Voeg je een endpoint toe dat iets wijzigt, verplaatst of schrijft, controleer dan dat het door
dezelfde guards loopt en niet als "read-only" is geclassificeerd.

**Bestandspaden**

Alles wat een pad uit config, een template of een plugin-request samenstelt, gaat via
`PathSafetyPolicy.swift` / `PlacementEngine.swift` — schrijfdoelen valideer je met
`PathSafetyPolicy.validateWriteTarget(_:projectMainFolder:)`. Path traversal (`../`) is eerder een
echt probleem geweest in `TemplateDeployer.swift`; daar zit nu een containment-check die het
opgebouwde pad `standardizedFileURL` maakt en tegen de root aftoetst (rond regel 118–130).
Nooit een pad uit externe input direct aan `FileManager` geven.

**Bestandsoperaties**

Deze app verplaatst bestanden van gebruikers. Dataverlies is de ergste bug die hier kan ontstaan:

- **Nooit delete-vóór-rename** en nooit stil overschrijven. Het patroon dat FileSafe gebruikt
  (`FileSafeTransferManager.swift`, rond regel 290–390) is: kopieer naar een temp-bestand,
  verifieer met een SHA-256-checksum, en verplaats dán pas naar de bestemming. Bestaat de
  bestemming al, dan wint identieke inhoud (duplicaat, klaar) en krijgt afwijkende inhoud een
  uniek pad via `uniqueDestination()` (`_2`, `_3`, …). Die helper bestaat twee keer, allebei
  `private`: `FileSafeTransferManager.swift:416` en `FileProcessor.swift:236`. Voeg je een derde
  pad toe, hergebruik dan een van die twee in plaats van zelf iets te verzinnen.
- Config-writes atomair — `try data.write(to:options: .atomic)`, zie `ConfigManager.swift:75`.

**Rechten minimaliseren**

Breid `FileFlower.entitlements`, de `permissions`/`host_permissions` in
`ChromeExtension/manifest.json` en de Safari-tegenhanger niet uit zonder concrete noodzaak.
De host-permissions zijn bewust per stock-site opgesomd; `<all_urls>` is geen optie.

**Analytics**

Alles wat naar Supabase gaat, gaat door `AnalyticsService.redactPII`. Geen bestandsnamen, paden,
project-namen, e-mailadressen of licentiesleutels in event-payloads.

### 3. Vertalingen

Nieuwe user-facing string → toevoegen aan `FileFlower/FileFlower/Localizable.xcstrings`.
Bron-taal is `en`; vertalingen voor `nl`, `de`, `fr`, `es`. Laat geen sleutel zonder vertaling
achter; het bestand is JSON en moet valide blijven (`python3 -m json.tool`).

### 4. Wat níét de repo in mag

`.gitignore` houdt interne documenten er bewust buiten — de repo is publiek:

- `audit-rapport-*.md` en `ik-vroeg-dit-aan-*.md` (interne audits en plannen)
- `.claude/`, `MacApp/config.json`, `dist/`, `build/`, `*.log`

Maak je een audit-, plan- of analysedocument, gebruik dan een van die patronen of zet het buiten
de git-root. Controleer met `git status --short` dat er niets ongewenst meelift.

## Releasen

Alleen op expliciet verzoek van de gebruiker.

1. **Versie bumpen** — `MARKETING_VERSION` en `CURRENT_PROJECT_VERSION` in
   `FileFlower/FileFlower.xcodeproj/project.pbxproj`. Vergelijk met de bovenste `<item>` in
   `appcast.xml`: als die gelijk zijn, is de huidige versie al uitgebracht en moet je bumpen.
   Bump ook `ChromeExtension/manifest.json` en `PremierePlugin_CEP/CSXS/manifest.xml` als die
   gewijzigd zijn.
2. `./scripts/bundle_plugins.sh`
3. `./scripts/build_dmg.sh` — signing + notarisatie + DMG. De Apple timestamp-server is soms
   instabiel; bij "timestamp service not available" gewoon opnieuw draaien.
4. `./scripts/create_release.sh` — interactief, maakt de GitHub-release.
5. `appcast.xml` handmatig bijwerken met de Sparkle-signature en pushen naar `main`.

## Bekende compiler-valkuil

De huidige toolchain (Apple Swift 6.2.4, effective Swift 5.10, `default-isolation=MainActor`)
**crasht** op een `Task.detached { ... await MainActor.run { self.x = ... } }` binnen een
SwiftUI `View`-struct. Symptoom: `Stack dump` + `While running pass ... "ClosureLifetimeFixup"`,
zonder `error:`-regel.

Workaround: houd zulke schijf-zware methodes synchroon, of gebruik een aparte `Task.detached` die
alleen waarde-types capteert en een `static func` aanroept (zie
`FileSafeProjectSelectView.scanProjects`). `buildPreview()` in `FileSafeView.swift` is daarom
bewust synchroon.

## Waar dingen staan

```
FileFlower/FileFlower/          macOS menubar-app (SwiftUI, geen dock-icoon)
  Models/                       Config, DownloadItem, Mapping, AnalyticsEvent, …
  Services/                     ~50 services: JobServer, Classifier, FileSafe*, Path*, License*
  Shared/                       Gedeeld met de FinderSync-extensie
  UI/                           Views
  Localizable.xcstrings         Alle strings, 5 talen
FileFlower/FileFlowerFinderSync/  Finder-extensie (folder deploy)
ChromeExtension/                Chrome MV3-extensie
SafariExtension/                Safari-extensie
PremierePlugin_CEP/             Premiere Pro CEP-plugin
ResolvePlugin/                  DaVinci Resolve Python-bridge
cloudflare-proxy/               Worker die de Anthropic- en Resend-calls proxied
scripts/                        Build-, release- en localisatie-scripts
appcast.xml                     Sparkle update-manifest
```

Config van de gebruiker: `~/Library/Application Support/FileFlower/config.json`.

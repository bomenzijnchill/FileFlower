# FileFlower Stock Helper - Chrome Extensie

Deze Chrome extensie scrapt metadata van stock muziek websites (Artlist, Epidemic Sound) en stuurt het automatisch naar de FileFlower Mac app.

## Installatie

### 1. Chrome extensie installeren (Developer mode)

1. Open Chrome en ga naar `chrome://extensions/`
2. Zet **Developer mode** aan (rechtsboven)
3. Klik op **Load unpacked**
4. Selecteer de `ChromeExtension` folder

### 2. FileFlower app starten

Zorg dat de FileFlower app actief is. De extensie communiceert met de app via `http://127.0.0.1:17890`.

## Gebruik

### Automatische metadata detectie

1. Ga naar een track pagina op **Artlist** of **Epidemic Sound**
2. De extensie scrapt automatisch:
   - Titel
   - Artist(s)
   - Genres
   - Moods
   - BPM
   - Duration
3. Klik op **Download** op de website
4. De metadata wordt automatisch naar de Mac app gestuurd
5. De Mac app koppelt de metadata aan het gedownloade bestand

### Popup

Klik op het extensie icoon om te zien:
- Of de Mac app verbonden is
- De huidige gescrapete metadata

## Ondersteunde websites

- ✅ **Artlist** (artlist.io)
- ✅ **Epidemic Sound** (epidemicsound.com)
- 🔜 MotionArray (coming soon)
- 🔜 Envato Elements (coming soon)

## Technische details

### Architectuur

```
┌─────────────────┐     ┌────────────────┐     ┌─────────────────┐
│  Stock Website  │ ──► │ Content Script │ ──► │ Background.js   │
│  (Artlist, etc) │     │ (DOM scraper)  │     │ (Service Worker)│
└─────────────────┘     └────────────────┘     └────────┬────────┘
                                                        │
                                                        │ HTTP POST
                                                        ▼
                                               ┌────────────────┐
                                               │ FileFlower   │
                                               │ Mac App        │
                                               │ (port 17890)   │
                                               └────────────────┘
```

### API Endpoint

De extensie stuurt metadata naar:

```
POST http://127.0.0.1:17890/stock-metadata
Content-Type: application/json

{
  "provider": "artlist",
  "pageUrl": "https://artlist.io/...",
  "downloadUrl": "https://...",
  "title": "Track Name",
  "artists": ["Artist 1"],
  "genres": ["Jazz", "Electronic"],
  "moods": ["Uplifting", "Happy"],
  "bpm": 120,
  "duration": 180
}
```

## Troubleshooting

### Extensie toont "FileFlower niet actief"
- Start de FileFlower app
- Check of de server draait op poort 17890

### Geen metadata gedetecteerd
- Zorg dat je op een track pagina bent (niet zoekresultaten)
- Refresh de pagina en wacht even
- Check de console (F12 > Console) voor errors

### Download wordt niet gekoppeld aan metadata
- Klik eerst op de track om metadata te laden
- Download binnen 60 seconden na het bezoeken van de pagina

## Development

### Console logs

De extensie logt naar de Chrome DevTools console:
- **Content script**: F12 op de webpagina
- **Background script**: `chrome://extensions/` > Details > Service Worker > Inspect

### Test de API

```bash
# Health check
curl http://127.0.0.1:17890/health

# Send test metadata
curl -X POST http://127.0.0.1:17890/stock-metadata \
  -H "Content-Type: application/json" \
  -d '{"provider":"test","title":"Test Track","genres":["Electronic"],"moods":["Happy"]}'
```





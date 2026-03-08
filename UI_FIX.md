# UI & Menubalk Icoon Fix

## Probleem
De app draait maar:
- Geen menubalk icoon zichtbaar
- Geen UI popover

## Oplossingen

### 1. App Sandbox Uitzetten (BELANGRIJK!)

In Xcode:
1. Selecteer project → Target "FileFlower"
2. Tab "Signing & Capabilities"
3. **Verwijder "App Sandbox" capability** of zet uit

Dit is nodig voor:
- Network binding (HTTP server)
- File system access (Downloads folder)

### 2. Menubalk Icoon Controleren

Na rebuild zou je moeten zien:
- Icoon in menubalk (rechtsboven, naast klok)
- Klik op icoon → popover verschijnt met UI

### 3. Als Icoon Nog Steeds Niet Verschijnt

Check in Xcode:
- Build & Run (Cmd+R)
- Check Console voor errors
- Verifieer dat app niet crasht bij start

### 4. Test de UI

1. Klik op menubalk icoon
2. Popover zou moeten verschijnen met:
   - "Geen downloads in wachtrij" (als leeg)
   - Of queue lijst (als er downloads zijn)
3. Klik "Instellingen" → Settings window

### 5. Runtime Error Fix

De "Operation not permitted" errors komen door App Sandbox.
**Zet App Sandbox uit** zoals beschreven in stap 1.

Na App Sandbox uitzetten:
- HTTP server zou moeten starten zonder errors
- Menubalk icoon zou moeten verschijnen
- UI zou moeten werken


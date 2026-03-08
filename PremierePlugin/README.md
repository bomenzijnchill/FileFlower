# FileFlower Premiere Plugin

UXP plugin voor Adobe Premiere Pro die communiceert met de FileFlower macOS app.

## Installatie

1. Kopieer de `PremierePlugin` folder naar:
   - macOS: `~/Library/Application Support/Adobe/CEP/extensions/`
   - Of gebruik de UXP Developer Tools voor development

2. Zorg dat de macOS app draait en de HTTP server actief is op `http://127.0.0.1:17890`

3. Start Premiere Pro en open de plugin via Window > Extensions > FileFlower Bridge

## Functionaliteit

- Pollt elke seconde naar nieuwe import jobs
- Opent projecten automatisch indien nodig
- Maakt bins aan volgens de opgegeven pad structuur
- Importeert bestanden in de juiste bins
- Rapporteert resultaten terug naar de macOS app

## Development

Voor development met UXP Developer Tools:

1. Installeer UXP Developer Tools
2. Open de plugin folder in UXP Developer Tools
3. Test met Premiere Pro

## ExtendScript Bridge

De plugin gebruikt ExtendScript via de CSInterface API om toegang te krijgen tot de Premiere Pro API. Zorg dat je Premiere Pro 23.0.0 of hoger gebruikt.


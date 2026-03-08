# FileFlower CEP Plugin

CEP (Common Extensibility Platform) plugin voor Adobe Premiere Pro die communiceert met de FileFlower macOS app.

## Installatie

1. **Kopieer de plugin folder naar CEP extensions directory:**
   ```bash
   cp -r PremierePlugin_CEP ~/Library/Application\ Support/Adobe/CEP/extensions/FileFlowerBridge
   ```

2. **Zorg dat CEP extensies enabled zijn:**
   - Open Terminal
   - Run: `defaults write com.adobe.CSXS.Player LogLevel 5`
   - Run: `defaults write com.adobe.CSXS.10 LogLevel 5`
   - Herstart Premiere Pro

3. **Zorg dat de macOS app draait:**
   - De HTTP server moet actief zijn op `http://127.0.0.1:17890`

4. **Start Premiere Pro:**
   - Window > Extensions > FileFlower Bridge

## Functionaliteit

- Pollt elke seconde naar nieuwe import jobs van de macOS app
- Opent projecten automatisch indien nodig
- Maakt bins aan volgens de opgegeven pad structuur
- Importeert bestanden in de juiste bins
- Rapporteert resultaten terug naar de macOS app

## Troubleshooting

- Check CEP logs: `~/Library/Logs/Adobe/CEP/`
- Verifieer dat CSInterface.js aanwezig is in de plugin folder
- Zorg dat Premiere Pro 23.0.0 of hoger gebruikt wordt
- Check dat de macOS app HTTP server actief is

## Verschil met UXP

CEP is de oudere maar stabielere technologie voor Premiere Pro extensies. UXP is nieuwer maar kan compatibiliteitsproblemen hebben. Deze CEP versie is gebaseerd op je werkende eerdere plugin.


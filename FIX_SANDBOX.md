# App Sandbox Fix

De runtime error "Operation not permitted" komt omdat App Sandbox enabled is. 

## Oplossing

In Xcode:
1. Selecteer het project in de navigator
2. Selecteer het target "FileFlower"
3. Ga naar tabblad "Signing & Capabilities"
4. **Schakel "App Sandbox" UIT** (of verwijder de capability)

De app heeft toegang nodig tot:
- File system (Downloads folder)
- Network (localhost HTTP server)
- User files (project roots)

Als je App Sandbox aan wilt houden, voeg dan deze capabilities toe:
- Outgoing Connections (Client)
- Incoming Connections (Server) 
- User Selected File (Read/Write)
- Downloads Folder (Read/Write)

Maar voor development is het makkelijker om App Sandbox uit te zetten.


# vendor/ — meegebundelde downloadtools

Deze map bevat de binaries die `build_dmg.sh` als gesigneerde helpers in
`FileFlower.app/Contents/Helpers/` bundelt voor de link-downloader. De
binaries zelf staan niet in git; vul de map met exact deze bestanden en
verifieer de herkomst met de checksums hieronder.

| bestand  | bron (officiële release)                                              | sha256 |
| -------- | --------------------------------------------------------------------- | ------ |
| `yt-dlp` | github.com/yt-dlp/yt-dlp — release 2026.08.19, asset `yt-dlp_macos` (universal) | `0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202` |
| `ffmpeg` | github.com/eugeneware/ffmpeg-static — release b6.1.1, assets `ffmpeg-darwin-arm64` + `ffmpeg-darwin-x64`, samengevoegd met `lipo -create` | arm64-deel: `a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584` · x64-deel: `ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894` |

Nieuwe versie bundelen: download de assets van de officiële release,
controleer ze tegen de door het project gepubliceerde checksums, voeg de twee
ffmpeg-slices samen met `lipo -create`, en werk deze tabel bij.

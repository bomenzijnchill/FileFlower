# MLX Classificatie Setup

Deze applicatie ondersteunt MLX-gebaseerde classificatie voor betere bestandsclassificatie op basis van filenames en metadata.

## Vereisten

1. **Python 3.8+** met pip
2. **MLX en MLX-LM** packages
3. **Apple Silicon Mac** (M1/M2/M3) voor optimale performance

## Installatie

### 1. Installeer MLX dependencies

```bash
pip install mlx mlx-lm
```

### 2. Download en converteer model

Het model wordt automatisch gedownload bij eerste gebruik, maar je kunt het ook handmatig downloaden:

```bash
python3 scripts/download_mlx_model.py \
  --model TinyLlama/TinyLlama-1.1B-Chat-v1.0 \
  --output ~/Library/Application\ Support/FileFlower/Models/TinyLlama-1.1B-Chat-v1.0
```

### 3. Activeer MLX classificatie in de app

1. Open de Settings in de app
2. Schakel "Use MLX Classification" in
3. Kies het model (standaard: TinyLlama-1.1B-Chat-v1.0)
4. Sla de configuratie op

## Beschikbare Modellen

### TinyLlama-1.1B-Chat-v1.0 (Aanbevolen)
- **Grootte**: ~700MB (gequantiseerd)
- **Snelheid**: Zeer snel (< 500ms per bestand)
- **Accuratie**: Goed voor basis classificatie
- **Model**: `TinyLlama/TinyLlama-1.1B-Chat-v1.0`

### Phi-3-mini-4k-instruct (Alternatief)
- **Grootte**: ~2.5GB (gequantiseerd)
- **Snelheid**: Sneller dan volledig model, maar langzamer dan TinyLlama
- **Accuratie**: Beter dan TinyLlama
- **Model**: `mlx-community/Phi-3-mini-4k-instruct-4bit`

## Model Locatie

Modellen worden opgeslagen in:
```
~/Library/Application Support/FileFlower/Models/
```

## Troubleshooting

### Model download faalt

1. Check of Python 3 geïnstalleerd is: `python3 --version`
2. Check of MLX geïnstalleerd is: `pip list | grep mlx`
3. Check internet connectie
4. Probeer handmatig te downloaden (zie boven)

### Classificatie is te langzaam

1. Gebruik een kleiner model (TinyLlama)
2. Zorg dat het model gequantiseerd is (4-bit)
3. Check GPU thermale status - de app throttlet automatisch bij hoge temperaturen

### Classificatie faalt

1. Check of het model correct gedownload is
2. Check of Python scripts executable zijn: `chmod +x scripts/*.py`
3. Check logs voor error messages
4. Fallback naar heuristische classificatie gebeurt automatisch

## Performance Tips

- **Batch Processing**: De app verwerkt bestanden in batches voor betere performance
- **Thermal Management**: De app monitort GPU temperatuur en throttlet automatisch
- **Caching**: Classificatie resultaten worden gecached voor identieke inputs
- **Fallback**: Bij MLX failures valt de app automatisch terug op heuristische classificatie

## Configuratie

MLX classificatie kan geconfigureerd worden in `Config.swift`:

```swift
var useMLXClassification: Bool = false
var mlxModelPath: String? = nil
var mlxModelName: String = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
```

## Scripts

- `scripts/download_mlx_model.py`: Download en converteer MLX models
- `scripts/mlx_classifier.py`: Classificeer bestanden met MLX model

Beide scripts zijn executable en kunnen handmatig gebruikt worden voor testing.


#!/usr/bin/env python3
"""
Script om een MLX model te downloaden en converteren.
Gebruikt mlx-lm om modellen te downloaden en te quantiseren.
"""

import argparse
import sys
import os
from pathlib import Path

def download_model(model_name: str, output_dir: str, quantize: bool = True):
    """
    Download en converteer een model naar MLX format.
    
    Args:
        model_name: Naam van het model (bijv. "mlx-community/TinyLlama-1.1B-Chat-v1.0")
        output_dir: Directory waar het model opgeslagen moet worden
        quantize: Of het model gequantiseerd moet worden (4-bit voor snelheid)
    """
    try:
        import mlx_lm
    except ImportError:
        print("ERROR: mlx-lm is niet geïnstalleerd.")
        print("Installeer met: pip install mlx-lm")
        sys.exit(1)
    
    output_path = Path(output_dir)
    
    # Verwijder directory als die al bestaat en leeg is, of als er geen belangrijke bestanden in zitten
    if output_path.exists():
        # Check of er belangrijke bestanden zijn (config.json betekent dat model al bestaat)
        config_file = output_path / "config.json"
        if not config_file.exists():
            # Directory bestaat maar heeft geen model - verwijder het
            print(f"Verwijderen van lege directory: {output_path}")
            import shutil
            shutil.rmtree(output_path)
        else:
            print(f"Model bestaat al in: {output_path}")
            print("Gebruik een andere output directory of verwijder de bestaande directory handmatig.")
            return False
    
    # Maak parent directory aan, maar niet de output directory zelf
    # mlx_lm.convert() maakt de output directory zelf aan
    if output_path.parent.exists() == False:
        output_path.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"Downloaden van model: {model_name}")
    print(f"Output directory: {output_path}")
    
    try:
        if quantize:
            print("Model wordt gequantiseerd naar 4-bit voor betere performance...")
            mlx_lm.convert(
                hf_path=model_name,
                mlx_path=str(output_path),
                quantize=True,
                q_group_size=64,
                q_bits=4
            )
        else:
            mlx_lm.convert(
                hf_path=model_name,
                mlx_path=str(output_path)
            )
        
        print(f"Model succesvol gedownload naar: {output_path}")
        return True
    except Exception as e:
        print(f"ERROR bij downloaden model: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Download MLX model")
    parser.add_argument(
        "--model",
        type=str,
        default="TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        help="Model naam (default: TinyLlama/TinyLlama-1.1B-Chat-v1.0)"
    )
    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="Output directory voor het model"
    )
    parser.add_argument(
        "--no-quantize",
        action="store_true",
        help="Gebruik geen quantisatie (langzamer maar accurater)"
    )
    
    args = parser.parse_args()
    
    success = download_model(
        model_name=args.model,
        output_dir=args.output,
        quantize=not args.no_quantize
    )
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()


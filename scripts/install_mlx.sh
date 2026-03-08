#!/bin/bash

# Script om MLX dependencies te installeren

set -e

echo "Installing MLX dependencies..."

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is niet geïnstalleerd"
    exit 1
fi

# Check pip
if ! command -v pip3 &> /dev/null; then
    echo "ERROR: pip3 is niet geïnstalleerd"
    exit 1
fi

# Install MLX packages
echo "Installing mlx and mlx-lm..."
pip3 install mlx mlx-lm

echo "MLX dependencies succesvol geïnstalleerd!"
echo ""
echo "Je kunt nu een model downloaden met:"
echo "  python3 scripts/download_mlx_model.py --model TinyLlama/TinyLlama-1.1B-Chat-v1.0 --output ~/Library/Application\\ Support/FileFlower/Models/TinyLlama-1.1B-Chat-v1.0"


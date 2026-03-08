#!/usr/bin/env python3
"""
MLX Classifier Script
Classificeert bestanden op basis van filename en metadata met behulp van MLX.
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Optional, Dict, Any

def load_model(model_path: str):
    """Laad het MLX model en tokenizer."""
    try:
        from mlx_lm import load
        model, tokenizer = load(str(model_path))
        return model, tokenizer
    except ImportError:
        print("ERROR: mlx of mlx-lm is niet geïnstalleerd.", file=sys.stderr)
        print("Installeer met: pip install mlx mlx-lm", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR bij laden model: {e}", file=sys.stderr)
        sys.exit(1)

def create_prompt(filename: str, metadata: Optional[Dict[str, Any]] = None) -> str:
    """
    Maak een classificatie prompt op basis van filename en metadata.
    
    Args:
        filename: Bestandsnaam
        metadata: Optionele metadata dictionary
    
    Returns:
        Prompt string voor het model
    """
    # Check for STEMS first - if filename contains STEMS keywords, it's definitely Music
    filename_lower = filename.lower()
    stems_keywords = ["stems", "stem", "bass", "drums", "instruments", "melody", "vocals", "vocal"]
    has_stems = any(keyword in filename_lower for keyword in stems_keywords)
    
    # Extract belangrijke info
    title = metadata.get("title", "") if metadata else ""
    artist = metadata.get("artist", "") if metadata else ""
    duration = metadata.get("duration") if metadata else None
    
    # Check voor verschillende types
    title_lower = title.lower() if title else ""
    
    # SFX keywords - specifieke sound effect beschrijvingen
    sfx_keywords = ["wind", "impact", "whoosh", "crash", "ambient", "nature", "organic", "soft", "long", 
                   "sfx", "sound effect", "clicks", "suction", "syringe", "animal", "animals", "mechanical",
                   "foley", "footstep", "door", "button", "click", "beep", "buzz", "hum"]
    
    # Muziek indicators - artiest namen, song titels, muzikale termen
    music_keywords = ["lover", "song", "track", "music", "beat", "melody", "artist", "producer", "composer"]
    has_artist = bool(artist) or " - " in filename  # Artiest naam pattern: "Song - Artist"
    
    # VO keywords
    vo_keywords = ["voice", "narration", "spoken", "dialogue", "narrator", "speech", "vo"]
    
    has_sfx_keyword = any(keyword in filename_lower or keyword in title_lower for keyword in sfx_keywords)
    has_music_keyword = any(keyword in filename_lower or keyword in title_lower for keyword in music_keywords)
    has_vo_keyword = any(keyword in filename_lower or keyword in title_lower for keyword in vo_keywords)
    
    # Audio file extension check - als het een audio bestand is en we hebben duidelijke signalen, 
    # dan direct classificeren zonder MLX
    audio_extensions = [".wav", ".mp3", ".aiff", ".aif", ".m4a", ".aac", ".flac", ".ogg"]
    is_audio = any(filename_lower.endswith(ext) for ext in audio_extensions)
    
    # DIRECT CLASSIFICATIE zonder MLX voor duidelijke gevallen
    # Dit voorkomt dat het model rare dingen retourneert
    if has_stems:
        # STEMS = altijd Music
        return "DIRECT:Music"
    
    if has_vo_keyword:
        # VO keywords = Voice Over
        return "DIRECT:VO"
    
    if has_sfx_keyword and not has_music_keyword and not has_artist:
        # SFX keywords zonder muziek indicators = SFX
        return "DIRECT:SFX"
    
    if has_artist or has_music_keyword:
        # Artist pattern of muziek keywords = Music
        return "DIRECT:Music"
    
    if is_audio and duration and duration >= 30:
        # Audio bestand langer dan 30s = waarschijnlijk Music
        return "DIRECT:Music"
    
    if is_audio and duration and duration < 10:
        # Audio bestand korter dan 10s = waarschijnlijk SFX
        return "DIRECT:SFX"
    
    if is_audio:
        # Default voor audio bestanden = Music (meest voorkomend)
        return "DIRECT:Music"
    
    # Alleen voor niet-duidelijke gevallen: gebruik MLX model
    prompt = f"""Classify this file. Only respond with JSON.
File: {filename}
"""
    
    if title:
        prompt += f"Title: {title}\n"
    if artist:
        prompt += f"Artist: {artist}\n"
    if duration is not None:
        prompt += f"Duration: {duration}s\n"
    
    prompt += """
Valid types: Music, SFX, VO
{"assetType": "Music", "genre": null, "mood": null}"""
    
    return prompt

def classify(model, tokenizer, prompt: str, max_tokens: int = 150) -> Dict[str, Any]:
    """
    Classificeer een bestand met het MLX model.
    
    Args:
        model: Geladen MLX model
        tokenizer: Tokenizer voor het model
        prompt: Classificatie prompt
        max_tokens: Maximum aantal tokens voor response
    
    Returns:
        Dictionary met classificatie resultaten
    """
    try:
        from mlx_lm import generate
        
        # Generate response - signature: generate(model, tokenizer, prompt, verbose=False, **kwargs)
        # max_tokens kan als keyword argument
        response = generate(
            model,
            tokenizer,
            prompt,
            max_tokens=max_tokens,
            verbose=False
        )
        
        # Parse JSON uit response
        response_text = response.strip()
        
        # Verwijder markdown code blocks als die er zijn
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0].strip()
        elif "```" in response_text:
            parts = response_text.split("```")
            if len(parts) >= 3:
                response_text = parts[1].strip()
        
        # Zoek naar JSON object in de response - pak alleen het eerste complete object
        start_idx = response_text.find("{")
        
        if start_idx >= 0:
            # Zoek het einde van het eerste JSON object door brackets te tellen
            bracket_count = 0
            end_idx = start_idx
            
            for i in range(start_idx, len(response_text)):
                if response_text[i] == '{':
                    bracket_count += 1
                elif response_text[i] == '}':
                    bracket_count -= 1
                    if bracket_count == 0:
                        end_idx = i
                        break
            
            if bracket_count == 0 and end_idx > start_idx:
                json_text = response_text[start_idx:end_idx+1]
                try:
                    result = json.loads(json_text)
                    return result
                except json.JSONDecodeError as e:
                    # Probeer nogmaals met strippen van whitespace
                    json_text = json_text.strip()
                    try:
                        result = json.loads(json_text)
                        return result
                    except json.JSONDecodeError:
                        raise ValueError(f"JSON decode error: {e}, text: {json_text}")
            else:
                raise ValueError(f"Incomplete JSON object in response: {response_text}")
        else:
            # Geen JSON gevonden
            raise ValueError(f"No JSON object found in response: {response_text}")
        
    except Exception as e:
        print(f"ERROR bij classificatie: {e}", file=sys.stderr)
        return {
            "assetType": "Unknown",
            "genre": None,
            "mood": None,
            "error": str(e)
        }

def main():
    parser = argparse.ArgumentParser(description="Classificeer bestand met MLX")
    parser.add_argument(
        "--model-path",
        type=str,
        required=True,
        help="Pad naar MLX model directory"
    )
    parser.add_argument(
        "--filename",
        type=str,
        required=True,
        help="Bestandsnaam om te classificeren"
    )
    parser.add_argument(
        "--metadata",
        type=str,
        help="JSON string met metadata (optioneel)"
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=150,
        help="Maximum aantal tokens voor response (default: 150)"
    )
    
    args = parser.parse_args()
    
    # Parse metadata
    metadata = None
    if args.metadata:
        try:
            metadata = json.loads(args.metadata)
        except json.JSONDecodeError:
            print(f"WARNING: Kon metadata niet parsen: {args.metadata}", file=sys.stderr)
    
    # Maak prompt (kan DIRECT: prefix retourneren voor duidelijke gevallen)
    prompt = create_prompt(args.filename, metadata)
    
    # Check voor directe classificatie (zonder MLX model)
    if prompt.startswith("DIRECT:"):
        asset_type = prompt.replace("DIRECT:", "")
        result = {
            "assetType": asset_type,
            "genre": None,
            "mood": None
        }
        print(json.dumps(result, indent=2))
        return 0
    
    # Laad model en tokenizer (alleen als we MLX nodig hebben)
    model, tokenizer = load_model(args.model_path)
    
    # Classificeer met MLX
    result = classify(model, tokenizer, prompt, max_tokens=args.max_tokens)
    
    # Output JSON
    print(json.dumps(result, indent=2))
    
    return 0

if __name__ == "__main__":
    sys.exit(main())


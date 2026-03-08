#!/usr/bin/env python3
"""
MLX Daemon - Persistent HTTP server voor snelle classificatie.
Het model wordt EEN keer geladen en blijft in memory voor instant responses.

Usage:
    python3 mlx_daemon.py --model-path /path/to/model --port 17891
    
API Endpoints:
    GET  /health         - Health check
    POST /classify       - Classificeer bestand
    POST /shutdown       - Stop de daemon
"""

import json
import sys
import argparse
import signal
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from typing import Optional, Dict, Any
import time

# Globale variabelen voor model en server
model = None
tokenizer = None
server = None
server_thread = None
model_loaded = False
model_loading = False
model_load_error = None

def load_model_async(model_path: str):
    """Laad het MLX model in een background thread."""
    global model, tokenizer, model_loaded, model_loading, model_load_error
    
    model_loading = True
    model_load_error = None
    
    try:
        print(f"[MLX Daemon] Loading model from {model_path}...", flush=True)
        start_time = time.time()
        
        from mlx_lm import load
        model, tokenizer = load(str(model_path))
        
        elapsed = time.time() - start_time
        print(f"[MLX Daemon] Model loaded in {elapsed:.2f}s", flush=True)
        
        model_loaded = True
        model_loading = False
        
    except ImportError as e:
        model_load_error = f"MLX not installed: {e}"
        print(f"[MLX Daemon] ERROR: {model_load_error}", file=sys.stderr, flush=True)
        model_loading = False
        
    except Exception as e:
        model_load_error = str(e)
        print(f"[MLX Daemon] ERROR loading model: {e}", file=sys.stderr, flush=True)
        model_loading = False


def create_prompt(filename: str, metadata: Optional[Dict[str, Any]] = None) -> str:
    """
    Maak een classificatie prompt op basis van filename en metadata.
    Retourneert "DIRECT:Type" voor duidelijke gevallen.
    """
    filename_lower = filename.lower()
    
    # Extract belangrijke info
    title = metadata.get("title", "") if metadata else ""
    artist = metadata.get("artist", "") if metadata else ""
    duration = metadata.get("duration") if metadata else None
    
    title_lower = title.lower() if title else ""
    
    # SFX keywords
    sfx_keywords = ["wind", "impact", "whoosh", "crash", "ambient", "nature", "organic",
                   "sfx", "sound effect", "clicks", "foley", "footstep", "door", "button", 
                   "click", "beep", "buzz", "hum", "riser", "downer", "swoosh"]
    
    # Music keywords
    music_keywords = ["song", "track", "music", "beat", "melody", "artist", "producer", 
                     "composer", "remix", "album"]
    
    # VO keywords
    vo_keywords = ["voice", "narration", "spoken", "dialogue", "narrator", "speech", "vo"]
    
    # STEMS keywords
    stems_keywords = ["stems", "stem", "bass", "drums", "instruments", "melody", "vocals", "vocal"]
    
    has_stems = any(keyword in filename_lower for keyword in stems_keywords)
    has_sfx = any(keyword in filename_lower or keyword in title_lower for keyword in sfx_keywords)
    has_music = any(keyword in filename_lower or keyword in title_lower for keyword in music_keywords)
    has_vo = any(keyword in filename_lower or keyword in title_lower for keyword in vo_keywords)
    has_artist = bool(artist) or " - " in filename
    
    # Audio extensions
    audio_extensions = [".wav", ".mp3", ".aiff", ".aif", ".m4a", ".aac", ".flac", ".ogg"]
    is_audio = any(filename_lower.endswith(ext) for ext in audio_extensions)
    
    # Direct classificatie voor duidelijke gevallen
    if has_stems:
        return "DIRECT:Music"
    
    if has_vo:
        return "DIRECT:VO"
    
    if has_sfx and not has_music and not has_artist:
        return "DIRECT:SFX"
    
    if has_artist or has_music:
        return "DIRECT:Music"
    
    if is_audio and duration and duration >= 30:
        return "DIRECT:Music"
    
    if is_audio and duration and duration < 10:
        return "DIRECT:SFX"
    
    if is_audio:
        return "DIRECT:Music"
    
    # MLX prompt voor niet-duidelijke gevallen
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


def classify_with_model(prompt: str, max_tokens: int = 150) -> Dict[str, Any]:
    """Classificeer met het geladen MLX model."""
    global model, tokenizer
    
    if not model_loaded or model is None or tokenizer is None:
        return {
            "assetType": "Unknown",
            "genre": None,
            "mood": None,
            "error": "Model not loaded"
        }
    
    try:
        from mlx_lm import generate
        
        response = generate(
            model,
            tokenizer,
            prompt,
            max_tokens=max_tokens,
            verbose=False
        )
        
        response_text = response.strip()
        
        # Parse JSON uit response
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0].strip()
        elif "```" in response_text:
            parts = response_text.split("```")
            if len(parts) >= 3:
                response_text = parts[1].strip()
        
        # Zoek naar JSON object
        start_idx = response_text.find("{")
        if start_idx >= 0:
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
                return json.loads(json_text)
        
        return {
            "assetType": "Unknown",
            "genre": None,
            "mood": None,
            "error": "No JSON in response"
        }
        
    except Exception as e:
        return {
            "assetType": "Unknown",
            "genre": None,
            "mood": None,
            "error": str(e)
        }


class DaemonHandler(BaseHTTPRequestHandler):
    """HTTP request handler voor de MLX daemon."""
    
    def log_message(self, format, *args):
        """Override om logs naar stdout te sturen."""
        print(f"[MLX Daemon] {args[0]}", flush=True)
    
    def send_json_response(self, data: dict, status: int = 200):
        """Stuur een JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_GET(self):
        """Handle GET requests."""
        if self.path == '/health':
            self.send_json_response({
                "status": "running",
                "model_loaded": model_loaded,
                "model_loading": model_loading,
                "error": model_load_error
            })
        else:
            self.send_json_response({"error": "Not found"}, 404)
    
    def do_POST(self):
        """Handle POST requests."""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else '{}'
        
        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self.send_json_response({"error": "Invalid JSON"}, 400)
            return
        
        if self.path == '/classify':
            self.handle_classify(data)
        elif self.path == '/shutdown':
            self.send_json_response({"status": "shutting_down"})
            # Shutdown in background thread
            threading.Thread(target=shutdown_server, daemon=True).start()
        else:
            self.send_json_response({"error": "Not found"}, 404)
    
    def handle_classify(self, data: dict):
        """Handle classificatie request."""
        filename = data.get('filename', '')
        metadata = data.get('metadata', {})
        max_tokens = data.get('max_tokens', 150)
        
        if not filename:
            self.send_json_response({"error": "filename required"}, 400)
            return
        
        # Check of model nog aan het laden is
        if model_loading:
            self.send_json_response({
                "assetType": "Unknown",
                "genre": None,
                "mood": None,
                "error": "Model is loading, please wait",
                "status": "loading"
            })
            return
        
        # Maak prompt
        prompt = create_prompt(filename, metadata)
        
        # Check voor directe classificatie
        if prompt.startswith("DIRECT:"):
            asset_type = prompt.replace("DIRECT:", "")
            self.send_json_response({
                "assetType": asset_type,
                "genre": None,
                "mood": None,
                "direct": True
            })
            return
        
        # Check of model geladen is
        if not model_loaded:
            self.send_json_response({
                "assetType": "Unknown",
                "genre": None,
                "mood": None,
                "error": model_load_error or "Model not loaded"
            })
            return
        
        # Classificeer met model
        start_time = time.time()
        result = classify_with_model(prompt, max_tokens)
        elapsed = time.time() - start_time
        
        result["processing_time_ms"] = int(elapsed * 1000)
        self.send_json_response(result)


def shutdown_server():
    """Stop de HTTP server."""
    global server
    print("[MLX Daemon] Shutting down...", flush=True)
    if server:
        server.shutdown()


def signal_handler(signum, frame):
    """Handle shutdown signals."""
    print(f"[MLX Daemon] Received signal {signum}", flush=True)
    shutdown_server()
    sys.exit(0)


def main():
    global server
    
    parser = argparse.ArgumentParser(description="MLX Classification Daemon")
    parser.add_argument(
        "--model-path",
        type=str,
        required=True,
        help="Path to MLX model directory"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=17891,
        help="Port to listen on (default: 17891)"
    )
    parser.add_argument(
        "--host",
        type=str,
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)"
    )
    
    args = parser.parse_args()
    
    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start model loading in background
    model_thread = threading.Thread(
        target=load_model_async,
        args=(args.model_path,),
        daemon=True
    )
    model_thread.start()
    
    # Start HTTP server
    server = HTTPServer((args.host, args.port), DaemonHandler)
    print(f"[MLX Daemon] Starting server on {args.host}:{args.port}", flush=True)
    print(f"[MLX Daemon] Model loading in background...", flush=True)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print("[MLX Daemon] Server stopped", flush=True)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())



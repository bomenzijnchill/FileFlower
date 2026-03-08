#!/usr/bin/env python3
"""
FileFlower DaVinci Resolve Bridge
Connects DaVinci Resolve's scripting API to the FileFlower JobServer.

This script:
1. Connects to DaVinci Resolve via the Scripting API
2. Reports the active project to FileFlower every ~2 seconds
3. Polls for new jobs from FileFlower every ~1 second
4. Creates folders in the Media Pool and imports files

Usage:
    python3 fileflower_resolve_bridge.py

Environment:
    PYTHONPATH must include the DaVinci Resolve scripting modules path:
    /Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules/
"""

import sys
import os
import time
import json
import re
import signal
from urllib.request import urlopen, Request
from urllib.error import URLError

# FileFlower JobServer configuration
JOBSERVER_HOST = "http://127.0.0.1:17890"
POLL_INTERVAL = 1.0         # Seconds between job polls
PROJECT_REPORT_INTERVAL = 2.0  # Seconds between active project reports
RESOLVE_CONNECT_INTERVAL = 5.0  # Seconds between Resolve connection attempts

# Globals
resolve = None
running = True

# Media root cache (per project)
_cached_media_root = None
_cached_media_root_project = None


def log(msg):
    """Print with flush for immediate output in subprocess."""
    print(f"[FileFlower Resolve Bridge] {msg}", flush=True)


def signal_handler(sig, frame):
    """Handle graceful shutdown."""
    global running
    log("Shutting down...")
    running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


def connect_resolve():
    """Try to connect to DaVinci Resolve via the scripting API."""
    global resolve
    try:
        import DaVinciResolveScript as dvr
        resolve = dvr.scriptapp("Resolve")
        if resolve is None:
            return False
        # Quick sanity check: try to get the product name
        name = resolve.GetProductName()
        if name:
            log(f"Connected to {name} {resolve.GetVersionString()}")
            return True
        resolve = None
        return False
    except ImportError:
        log("ERROR: DaVinciResolveScript module not found. Check PYTHONPATH.")
        return False
    except Exception as e:
        resolve = None
        return False


_http_error_counts = {}


def http_get(path):
    """Make a GET request to the JobServer. Returns parsed JSON or None."""
    try:
        req = Request(f"{JOBSERVER_HOST}{path}", method="GET")
        req.add_header("Content-Type", "application/json")
        with urlopen(req, timeout=5) as resp:
            data = resp.read().decode("utf-8")
            # Reset error count on success
            _http_error_counts[path] = 0
            return json.loads(data) if data else None
    except (URLError, Exception) as e:
        # Log eerste paar fouten per pad, daarna stil (voorkom log spam bij polling)
        count = _http_error_counts.get(path, 0) + 1
        _http_error_counts[path] = count
        if count <= 3:
            log(f"ERROR: http_get {path} failed ({count}x): {e}")
        elif count == 4:
            log(f"ERROR: http_get {path} failed {count}x, verdere fouten worden onderdrukt")
        return None


def http_post(path, payload):
    """Make a POST request to the JobServer. Returns parsed JSON or None."""
    try:
        body = json.dumps(payload).encode("utf-8")
        req = Request(f"{JOBSERVER_HOST}{path}", data=body, method="POST")
        req.add_header("Content-Type", "application/json")
        with urlopen(req, timeout=5) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data) if data else None
    except (URLError, Exception) as e:
        log(f"ERROR: http_post {path} failed: {e}")
        return None


def get_active_project_path():
    """Get the file path of the currently open Resolve project.

    DaVinci Resolve does not directly expose .drp file paths via scripting API.
    We use the project name + database path to reconstruct a best-effort path.

    For disk-based databases (the common case), the project file is at:
        <database_path>/Resolve Projects/Users/guest/Projects/<ProjectName>/<ProjectName>.drp

    For cloud databases (Blackmagic Cloud, PostgreSQL, DiskSAN), there are no local .drp files.
    In this case, we return a virtual path: /resolve-project/<ProjectName>/<ProjectName>.drp
    This virtual path is used by FileFlower for project name matching and works correctly
    because FileFlower matches projects by name, not by exact file path.

    Media Pool operations (ImportMedia, AddSubFolder, etc.) work identically for both
    local and cloud databases since they go through the Resolve scripting API.
    """
    if resolve is None:
        return None
    try:
        pm = resolve.GetProjectManager()
        if pm is None:
            return None
        project = pm.GetCurrentProject()
        if project is None:
            return None

        project_name = project.GetName()
        if not project_name:
            return None

        # Try to find the .drp file via the database path
        db_list = pm.GetDatabaseList()
        current_db = pm.GetCurrentDatabase()
        db_path = None

        if current_db and isinstance(current_db, dict):
            db_path = current_db.get("DbPath", None)

            # Check database type - cloud/network databases don't have local .drp files
            db_type = current_db.get("DbType", "Disk")
            if db_type and db_type.lower() in ("cloud", "disksan", "postgresql", "network"):
                log(f"Cloud/network database detected (type: {db_type}), using virtual path")
                return f"/resolve-project/{project_name}/{project_name}.drp"

        # For disk-based databases, construct the path
        if db_path and os.path.isdir(db_path):
            drp_path = os.path.join(
                db_path, "Resolve Projects", "Users", "guest", "Projects",
                project_name, f"{project_name}.drp"
            )
            if os.path.exists(drp_path):
                return drp_path

        # Fallback: search common Resolve database locations
        home = os.path.expanduser("~")
        common_paths = [
            os.path.join(home, "Documents", "Resolve Projects", "Users", "guest",
                         "Projects", project_name, f"{project_name}.drp"),
            os.path.join(home, "Library", "Application Support",
                         "Blackmagic Design", "DaVinci Resolve", "Resolve Disk Database",
                         "Resolve Projects", "Users", "guest", "Projects",
                         project_name, f"{project_name}.drp"),
        ]

        for path in common_paths:
            if os.path.exists(path):
                return path

        # If we can't find the .drp file, return a virtual path that FileFlower
        # can still use for project matching (name-based)
        return f"/resolve-project/{project_name}/{project_name}.drp"

    except Exception as e:
        log(f"Error getting project path: {e}")
        return None


def _collect_clip_paths(folder, paths):
    """Recursively collect file paths from all clips in a Media Pool folder.

    Args:
        folder: A Resolve MediaPool folder object
        paths: List to append file paths to (mutated in place)
    """
    clips = folder.GetClipList()
    if clips:
        for clip in clips:
            try:
                # GetClipProperty("File Path") returns the full filesystem path
                file_path = clip.GetClipProperty("File Path")
                if file_path and isinstance(file_path, str) and os.path.isabs(file_path):
                    paths.append(file_path)
            except Exception:
                pass

    subfolders = folder.GetSubFolderList()
    if subfolders:
        for subfolder in subfolders:
            _collect_clip_paths(subfolder, paths)


def scan_media_root():
    """Scan all clips in the Media Pool and compute the common parent directory.

    Recursively walks all folders in the Media Pool, reads the 'File Path' property
    from each clip, and uses os.path.commonpath() to find the shared root directory.

    Returns:
        str or None: The common parent directory of all clips, or None if:
            - No project is open
            - Media Pool is empty
            - Clips are on multiple drives (commonpath returns "/" or very short path)
            - An error occurs

    Results are cached per project name to avoid rescanning on every report cycle.
    """
    global _cached_media_root, _cached_media_root_project

    if resolve is None:
        return None

    try:
        pm = resolve.GetProjectManager()
        project = pm.GetCurrentProject() if pm else None
        if project is None:
            return None

        project_name = project.GetName()

        # Return cached result if same project
        if _cached_media_root_project == project_name and _cached_media_root is not None:
            return _cached_media_root

        media_pool = project.GetMediaPool()
        if media_pool is None:
            return None

        root_folder = media_pool.GetRootFolder()
        if root_folder is None:
            return None

        # Collect all clip file paths recursively
        file_paths = []
        _collect_clip_paths(root_folder, file_paths)

        if not file_paths:
            log(f"Media Pool is empty for project '{project_name}', no media root")
            _cached_media_root = None
            _cached_media_root_project = project_name
            return None

        # Compute common path
        if len(file_paths) == 1:
            # Single clip: use its parent directory
            media_root = os.path.dirname(file_paths[0])
        else:
            try:
                media_root = os.path.commonpath(file_paths)
            except ValueError:
                # Happens when paths are on different drives or mix of absolute/relative
                log("Clips are on different drives, cannot compute common path")
                _cached_media_root = None
                _cached_media_root_project = project_name
                return None

        # Safety check: reject overly broad roots
        if media_root == "/" or media_root == "" or len(media_root) < 4:
            log(f"Computed media root is too broad: '{media_root}', skipping")
            _cached_media_root = None
            _cached_media_root_project = project_name
            return None

        # If commonpath resolves to a file (not a directory), use its parent
        if os.path.isfile(media_root):
            media_root = os.path.dirname(media_root)

        # Verify the path exists on disk
        if not os.path.isdir(media_root):
            log(f"Computed media root does not exist: '{media_root}', skipping")
            _cached_media_root = None
            _cached_media_root_project = project_name
            return None

        log(f"Media root for '{project_name}': {media_root} (from {len(file_paths)} clips)")
        _cached_media_root = media_root
        _cached_media_root_project = project_name
        return media_root

    except Exception as e:
        log(f"Error scanning media root: {e}")
        return None


def invalidate_media_root_cache():
    """Clear the media root cache so it will be re-scanned on next access."""
    global _cached_media_root, _cached_media_root_project
    _cached_media_root = None
    _cached_media_root_project = None


def report_active_project():
    """Report the active project and media root to FileFlower's JobServer."""
    project_path = get_active_project_path()
    media_root = scan_media_root()

    payload = {"projectPath": project_path}
    if media_root:
        payload["mediaRoot"] = media_root

    # Include database type for debugging
    if resolve:
        try:
            pm = resolve.GetProjectManager()
            current_db = pm.GetCurrentDatabase() if pm else None
            if current_db and isinstance(current_db, dict):
                payload["dbType"] = current_db.get("DbType", "Disk")
        except Exception:
            pass

    http_post("/resolve/active-project", payload)


def normalize_name(name):
    """Normalize a folder name by removing number prefixes like '03_'.

    Used for fuzzy matching between Finder folder names and Media Pool folders.
    """
    # Remove leading number prefix (e.g., "03_Audio" -> "Audio")
    stripped = re.sub(r"^\d+[_\-\s]*", "", name)
    return stripped.lower().strip() if stripped else name.lower().strip()


def find_or_create_folder(media_pool, parent_folder, name):
    """Find a subfolder by name (fuzzy match) or create it.

    Supports fuzzy matching: ignores number prefixes like "03_".
    For example, looking for "Audio" will match "03_Audio".
    """
    normalized_target = normalize_name(name)

    # Check existing subfolders
    subfolders = parent_folder.GetSubFolderList()
    if subfolders:
        for folder in subfolders:
            folder_name = folder.GetName()
            if folder_name and normalize_name(folder_name) == normalized_target:
                return folder

    # Not found - create new folder
    new_folder = media_pool.AddSubFolder(parent_folder, name)
    if new_folder:
        log(f"Created Media Pool folder: {name}")
    return new_folder


def navigate_to_folder(media_pool, root_folder, path_components):
    """Navigate to a nested folder path, creating folders as needed.

    Args:
        media_pool: The Resolve MediaPool object
        root_folder: The root Media Pool folder to start from
        path_components: List of folder names forming the path

    Returns:
        The target MediaPool folder, or None on failure
    """
    current = root_folder
    for component in path_components:
        folder = find_or_create_folder(media_pool, current, component)
        if folder is None:
            log(f"Failed to create/find folder: {component}")
            return None
        current = folder
    return current


def process_job(job):
    """Process a single import job from the FileFlower JobServer.

    Args:
        job: Dict with keys: id, projectPath, premiereBinPath, files, finderTargetDir, etc.

    Returns:
        Dict with job result (success, importedFiles, failedFiles, error)
    """
    job_id = job.get("id", "unknown")
    bin_path = job.get("premiereBinPath", "")
    files = job.get("files", [])

    log(f"Processing job {job_id}: {len(files)} files -> '{bin_path}'")

    imported = []
    failed = []
    already_imported = []

    try:
        if resolve is None:
            return {
                "jobId": job_id, "success": False,
                "importedFiles": [], "failedFiles": files,
                "error": "Not connected to Resolve"
            }

        pm = resolve.GetProjectManager()
        project = pm.GetCurrentProject() if pm else None
        if project is None:
            return {
                "jobId": job_id, "success": False,
                "importedFiles": [], "failedFiles": files,
                "error": "No project open in Resolve"
            }

        media_pool = project.GetMediaPool()
        if media_pool is None:
            return {
                "jobId": job_id, "success": False,
                "importedFiles": [], "failedFiles": files,
                "error": "Could not access Media Pool"
            }

        # Navigate to the target folder in the Media Pool
        root_folder = media_pool.GetRootFolder()
        path_components = [c for c in bin_path.split("/") if c]

        if path_components:
            target_folder = navigate_to_folder(media_pool, root_folder, path_components)
        else:
            target_folder = root_folder

        if target_folder is None:
            return {
                "jobId": job_id, "success": False,
                "importedFiles": [], "failedFiles": files,
                "error": f"Could not navigate to folder: {bin_path}"
            }

        # Set the current folder so imports go to the right place
        media_pool.SetCurrentFolder(target_folder)

        # Import files one by one for granular reporting
        for file_path in files:
            if not os.path.exists(file_path):
                log(f"  File not found: {file_path}")
                failed.append(file_path)
                continue

            # Check if already imported (by checking clip names in current folder)
            file_name = os.path.basename(file_path)
            clips = target_folder.GetClipList()
            already_exists = False
            if clips:
                for clip in clips:
                    clip_name = clip.GetClipProperty("File Name")
                    if clip_name == file_name:
                        already_exists = True
                        break

            if already_exists:
                log(f"  Already imported: {file_name}")
                already_imported.append(file_path)
                continue

            # Import the file
            result = media_pool.ImportMedia([file_path])
            if result and len(result) > 0:
                log(f"  Imported: {file_name}")
                imported.append(file_path)
            else:
                log(f"  Failed to import: {file_name}")
                failed.append(file_path)

    except Exception as e:
        log(f"Error processing job: {e}")
        return {
            "jobId": job_id, "success": False,
            "importedFiles": imported, "failedFiles": files,
            "error": str(e)
        }

    success = len(failed) == 0
    result = {
        "jobId": job_id,
        "success": success,
        "importedFiles": imported,
        "failedFiles": failed,
        "error": None if success else f"{len(failed)} files failed",
        "alreadyImported": already_imported if already_imported else None
    }

    log(f"Job {job_id} complete: {len(imported)} imported, {len(failed)} failed, {len(already_imported)} already existed")
    return result


def main():
    """Main loop: connect to Resolve, poll JobServer, process jobs."""
    global resolve, running

    log("Starting FileFlower Resolve Bridge...")
    log(f"JobServer: {JOBSERVER_HOST}")
    log(f"Python: {sys.version}")
    log(f"PYTHONPATH: {os.environ.get('PYTHONPATH', 'not set')}")

    # Check JobServer connectivity
    health = http_get("/health")
    if health:
        log(f"JobServer is reachable: {health.get('status', 'unknown')}")
    else:
        log("WARNING: JobServer is not reachable. Will retry...")

    last_project_report = 0
    last_resolve_connect = 0
    last_project_name = None  # Track project name for cache invalidation

    while running:
        now = time.time()

        # Try to connect to Resolve if not connected
        if resolve is None:
            if now - last_resolve_connect >= RESOLVE_CONNECT_INTERVAL:
                last_resolve_connect = now
                if not connect_resolve():
                    time.sleep(POLL_INTERVAL)
                    continue

        # Verify Resolve is still connected
        try:
            if resolve and resolve.GetProductName() is None:
                log("Lost connection to Resolve")
                resolve = None
                time.sleep(POLL_INTERVAL)
                continue
        except Exception:
            log("Lost connection to Resolve")
            resolve = None
            time.sleep(POLL_INTERVAL)
            continue

        # Detect project change and invalidate media root cache
        try:
            if resolve:
                pm = resolve.GetProjectManager()
                current_project = pm.GetCurrentProject() if pm else None
                current_name = current_project.GetName() if current_project else None
                if current_name != last_project_name:
                    if last_project_name is not None:
                        log(f"Project changed: '{last_project_name}' -> '{current_name}'")
                        invalidate_media_root_cache()
                    last_project_name = current_name
        except Exception:
            pass

        # Report active project periodically
        if now - last_project_report >= PROJECT_REPORT_INTERVAL:
            last_project_report = now
            report_active_project()

        # Poll for next job
        job_data = http_get("/resolve/jobs/next")
        if job_data and "id" in job_data:
            result = process_job(job_data)
            job_id = job_data["id"]
            post_response = http_post(f"/resolve/jobs/{job_id}/result", result)
            if post_response:
                log(f"Job result posted successfully for {job_id}")
            else:
                log(f"ERROR: Failed to post job result for {job_id}")
        else:
            # No job available, sleep before next poll
            time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()

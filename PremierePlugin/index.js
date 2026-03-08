const BRIDGE_URL = "http://127.0.0.1:17890";
const POLL_INTERVAL = 200; // 200ms voor snellere respons

let pollInterval = null;
let isProcessing = false;

function updateStatus(message, className = "") {
    const statusEl = document.getElementById("status");
    statusEl.textContent = message;
    statusEl.className = `status ${className}`;
}

function log(message) {
    const logEl = document.getElementById("log");
    const time = new Date().toLocaleTimeString();
    logEl.innerHTML += `<div>[${time}] ${message}</div>`;
    logEl.scrollTop = logEl.scrollHeight;
}

async function pollForJobs() {
    if (isProcessing) {
        return;
    }
    
    try {
        const response = await fetch(`${BRIDGE_URL}/jobs/next`);
        
        if (response.status === 200) {
            const text = await response.text();
            if (!text || text.trim() === '') {
                updateStatus("Wachten op jobs...", "");
                return;
            }
            
            const data = JSON.parse(text);
            
            if (data.projectPath) {
                // Job found
                isProcessing = true;
                updateStatus("Job gevonden, verwerken...", "connected");
                log(`Job ontvangen: ${data.id}`);
                
                try {
                    await processJob(data);
                } catch (error) {
                    log(`Fout bij verwerken: ${error.message}`);
                    await sendResult(data.id, false, [], data.files, error.message);
                } finally {
                    isProcessing = false;
                }
            } else {
                updateStatus("Wachten op jobs...", "");
            }
        } else if (response.status === 204) {
            updateStatus("Wachten op jobs...", "");
        }
    } catch (error) {
        updateStatus("Verbindingsfout", "error");
        log(`Poll fout: ${error.message}`);
    }
}

async function processJob(job) {
    log(`Controleren project: ${job.projectPath}`);
    
    // Check and open project if needed (only if different project is open or no project is open)
    // If this fails, we'll continue anyway - maybe project is already open
    try {
        await ensureProjectOpen(job.projectPath);
    } catch (error) {
        log(`Waarschuwing bij project check: ${error.message} - doorgaan met importeren`);
        // Continue anyway - project might already be open
    }
    
    // Ensure bin exists
    log(`Bin aanmaken/vinden: ${job.premiereBinPath} (type: ${job.assetType || 'unknown'})`);
    const bin = await ensureBinPath(job.premiereBinPath, job.assetType);
    
    // Import files
    log(`Importeren van ${job.files.length} bestand(en)`);
    const result = await importFilesIntoBin(job.files, bin);
    
    // Send result
    await sendResult(
        job.id,
        result.success,
        result.importedFiles,
        result.failedFiles,
        result.error
    );
    
    log(`Job voltooid: ${result.importedFiles.length} geïmporteerd`);
}

async function ensureProjectOpen(projectPath) {
    return new Promise((resolve, reject) => {
        // Escape path for ExtendScript: escape backslashes, quotes, and newlines
        const escapedPath = projectPath
            .replace(/\\/g, "\\\\")
            .replace(/"/g, '\\"')
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r");
        
        const script = `
            (function() {
                try {
                    var targetPath = "${escapedPath}";
                    var targetFile = new File(targetPath);
                    
                    if (!targetFile.exists) {
                        return JSON.stringify({ success: false, error: "Project file does not exist: " + targetPath });
                    }
                    
                    // Check if the correct project is already open
                    var isCorrectProjectOpen = false;
                    var hasProject = false;
                    
                    try {
                        if (app.project) {
                            hasProject = true;
                            if (app.project.file) {
                                var currentPath = app.project.file.fsName;
                                var targetPathNormalized = targetFile.fsName;
                                
                                // Compare normalized paths (case-insensitive on Mac)
                                if (currentPath.toLowerCase() === targetPathNormalized.toLowerCase()) {
                                    isCorrectProjectOpen = true;
                                }
                            }
                        }
                    } catch (e) {
                        // If check fails, assume no project is open
                        hasProject = false;
                        isCorrectProjectOpen = false;
                    }
                    
                    // Only open if the correct project is NOT already open
                    if (!isCorrectProjectOpen) {
                        // Only try to open if no project is open at all
                        if (!hasProject) {
                            try {
                                app.openDocument(targetFile);
                    return JSON.stringify({ success: true, message: "Project geopend" });
                            } catch (openError) {
                                // If open fails, continue anyway - maybe project is already open
                                return JSON.stringify({ success: true, message: "Project openen mislukt, doorgaan met importeren" });
                            }
                        } else {
                            // Different project is open - don't try to switch, just continue
                            return JSON.stringify({ success: true, message: "Ander project is open, doorgaan met importeren" });
                        }
                    } else {
                        return JSON.stringify({ success: true, message: "Juiste project is al open" });
                    }
                } catch (e) {
                    return JSON.stringify({ success: false, error: e.toString() });
                }
            })();
        `;
        
        // Use ExtendScript bridge via CSInterface
        if (typeof CSInterface !== 'undefined') {
            const csInterface = new CSInterface();
            csInterface.evalScript(script, (result) => {
                try {
                    const parsed = JSON.parse(result);
                    if (parsed.success) {
                        resolve(parsed);
                    } else {
                        // Don't reject - just log and continue
                        resolve({ success: true, message: "Project check gefaald, doorgaan: " + parsed.error });
                    }
                } catch (e) {
                    // Don't reject - just log and continue
                    resolve({ success: true, message: "Project check parse error, doorgaan" });
                }
            });
        } else {
            // Fallback for UXP - don't reject, just continue
            resolve({ success: true, message: "CSInterface not available, doorgaan" });
        }
    });
}

async function ensureBinPath(pathString, assetType) {
    return new Promise((resolve, reject) => {
        const parts = pathString.split("/").filter(p => p.length > 0);

        const script = `
            (function() {
                try {
                    var pathParts = ${JSON.stringify(parts)};
                    var assetType = ${JSON.stringify(assetType || "")};

                    // Keywords per asset type voor slim matchen
                    var keywordsByType = {
                        "Music": ["muziek", "music", "audio", "sound", "soundtrack", "score", "tracks", "songs", "musik", "musique"],
                        "SFX": ["sfx", "soundfx", "sound effects", "geluidseffecten", "foley", "effects", "effecten", "geluiden", "effekte"],
                        "VO": ["vo", "voice", "voiceover", "voice-over", "voice over", "ingesproken", "ingesproken tekst", "narration", "dialogue", "spraak"],
                        "Graphic": ["graphics", "graphic", "vormgeving", "design", "stills", "afbeeldingen", "images", "fotos", "photos", "grafik"],
                        "MotionGraphic": ["motion", "motion graphics", "motiongraphics", "animatie", "animation", "mogrt", "templates"],
                        "StockFootage": ["footage", "stock", "stockfootage", "stock footage", "beeldmateriaal", "b-roll", "broll", "shots", "visuals"]
                    };

                    // Haal keywords op voor het huidige asset type
                    var typeKeywords = keywordsByType[assetType] || [];

                    // Alle keywords (alle types) voor bredere matching
                    var allKeywords = {};
                    for (var t in keywordsByType) {
                        for (var ki = 0; ki < keywordsByType[t].length; ki++) {
                            allKeywords[keywordsByType[t][ki]] = t;
                        }
                    }

                    // Normalize: strip nummer-prefix en lowercase
                    var normalizeName = function(name) {
                        try {
                            if (!name) return "";
                            var nameStr = typeof name === "string" ? name : String(name);
                            if (!nameStr || nameStr === "undefined" || nameStr === "null") return "";

                            // Trim whitespace
                            var trimmed = nameStr;
                            var ws = " \\t\\n\\r";
                            while (trimmed.length > 0 && ws.indexOf(trimmed.charAt(0)) !== -1) {
                                trimmed = trimmed.substring(1);
                            }
                            while (trimmed.length > 0 && ws.indexOf(trimmed.charAt(trimmed.length - 1)) !== -1) {
                                trimmed = trimmed.substring(0, trimmed.length - 1);
                            }

                            if (typeof trimmed !== "string") return "";
                            var normalized = trimmed.toLowerCase();
                            if (typeof normalized !== "string") return "";

                            // Remove number prefix like "03_"
                            if (normalized.match(/^\\d+_/)) {
                                normalized = normalized.replace(/^\\d+_/, "");
                            }
                            return normalized;
                        } catch (e) {
                            return "";
                        }
                    };

                    // Zoek een bin in parent die matcht met searchName, met keyword-aware matching
                    var findBinInParent = function(parentBin, searchName, keywords) {
                        var normalizedSearch = normalizeName(searchName);

                        for (var i = 0; i < parentBin.children.numItems; i++) {
                            var child = parentBin.children[i];
                            if (!child || child.type !== ProjectItemType.BIN) continue;

                            var childName = child.name ? String(child.name) : "";
                            if (!childName) continue;
                            var childNorm = normalizeName(childName);

                            // 1. Exacte match
                            if (childName === searchName) return child;

                            // 2. Genormaliseerde match
                            if (childNorm === normalizedSearch) return child;

                            // 3. Substring match
                            if (childNorm.indexOf(normalizedSearch) !== -1 || normalizedSearch.indexOf(childNorm) !== -1) {
                                return child;
                            }

                            // 4. Keyword matching voor het specifieke asset type
                            if (keywords && keywords.length > 0) {
                                for (var k = 0; k < keywords.length; k++) {
                                    if (childNorm.indexOf(keywords[k]) !== -1 || keywords[k].indexOf(childNorm) !== -1) {
                                        return child;
                                    }
                                }
                            }
                        }
                        return null;
                    };

                    // Multi-level traversal: loop door alle pad-componenten
                    var currentBin = app.project.rootItem;

                    for (var p = 0; p < pathParts.length; p++) {
                        var part = pathParts[p];

                        // Bepaal welke keywords te gebruiken op dit niveau
                        // Op het eerste niveau: gebruik asset-type keywords
                        // Op diepere niveaus: gebruik ook asset-type keywords (bijv. 03_Audio/VO)
                        var keywords = typeKeywords;

                        var found = findBinInParent(currentBin, part, keywords);

                        if (found) {
                            currentBin = found;
                        } else {
                            // Bin niet gevonden - maak een nieuwe aan
                            currentBin = currentBin.createBin(part);
                        }
                    }

                    // Build bin path
                    var binPathParts = [];
                    var tempBin = currentBin;
                    while (tempBin && tempBin !== app.project.rootItem && tempBin.name) {
                        binPathParts.unshift(tempBin.name);
                        tempBin = tempBin.parent;
                    }
                    var binPath = binPathParts.join("/");

                    return JSON.stringify({ success: true, binPath: binPath });
                } catch (e) {
                    return JSON.stringify({ success: false, error: e.toString() });
                }
            })();
        `;

        if (typeof CSInterface !== 'undefined') {
            const csInterface = new CSInterface();
            csInterface.evalScript(script, (result) => {
                try {
                    const parsed = JSON.parse(result);
                    if (parsed.success) {
                        resolve(parsed);
                    } else {
                        reject(new Error(parsed.error || "Unknown error"));
                    }
                } catch (e) {
                    reject(e);
                }
            });
        } else {
            reject(new Error("CSInterface not available"));
        }
    });
}

async function importFilesIntoBin(files, bin) {
    return new Promise((resolve, reject) => {
        // Escape file paths for ExtendScript
        const escapedFiles = files.map(f => f.replace(/\\/g, "\\\\").replace(/"/g, '\\"'));
        
        const script = `
            (function() {
                try {
                    var files = ${JSON.stringify(escapedFiles)};
                    var imported = [];
                    var failed = [];
                    var targetBin = app.project.rootItem;
                    
                    // Find bin by path from bin object if provided
                    if (bin && bin.binPath) {
                        var parts = bin.binPath.split("/").filter(function(p) { return p.length > 0; });
                        for (var p = 0; p < parts.length; p++) {
                            var part = parts[p];
                            var found = false;
                            for (var q = 0; q < targetBin.children.numItems; q++) {
                                var child = targetBin.children[q];
                                if (child.name === part && child.type === ProjectItemType.BIN) {
                                    targetBin = child;
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) break;
                        }
                    }
                    
                    for (var i = 0; i < files.length; i++) {
                        try {
                            var file = new File(files[i]);
                            var folder = new Folder(files[i]);
                            
                            if (folder.exists && folder instanceof Folder) {
                                // Import folder - Premiere will import all contents
                                app.project.importFiles([folder.fsName], false, targetBin, 0);
                                imported.push(files[i]);
                            } else if (file.exists) {
                                // Import single file
                                app.project.importFiles([file.fsName], false, targetBin, 0);
                                imported.push(files[i]);
                            } else {
                                failed.push(files[i]);
                            }
                        } catch (e) {
                            failed.push(files[i]);
                        }
                    }
                    
                    return JSON.stringify({
                        success: failed.length === 0,
                        importedFiles: imported,
                        failedFiles: failed
                    });
                } catch (e) {
                    return JSON.stringify({
                        success: false,
                        importedFiles: [],
                        failedFiles: files,
                        error: e.toString()
                    });
                }
            })();
        `;
        
        if (typeof CSInterface !== 'undefined') {
            const csInterface = new CSInterface();
            csInterface.evalScript(script, (result) => {
                try {
                    const parsed = JSON.parse(result);
                    resolve(parsed);
                } catch (e) {
                    reject(e);
                }
            });
        } else {
            reject(new Error("CSInterface not available"));
        }
    });
}

async function sendResult(jobId, success, importedFiles, failedFiles, error) {
    try {
        const result = {
            jobId: jobId,
            success: success,
            importedFiles: importedFiles || [],
            failedFiles: failedFiles || [],
            error: error || null
        };
        
        await fetch(`${BRIDGE_URL}/jobs/${jobId}/result`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(result)
        });
    } catch (e) {
        log(`Fout bij verzenden resultaat: ${e.message}`);
    }
}

// Initialize
document.addEventListener("DOMContentLoaded", () => {
    updateStatus("Starten...", "");
    log("FileFlower Bridge gestart");
    
    // Start polling
    pollInterval = setInterval(pollForJobs, POLL_INTERVAL);
    pollForJobs(); // Immediate first poll
    
    updateStatus("Wachten op jobs...", "");
});



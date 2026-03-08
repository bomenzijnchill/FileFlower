// FileFlower CEP Bridge - Polls HTTP server from macOS app
const BRIDGE_URL = "http://127.0.0.1:17890";
const POLL_INTERVAL = 1000; // 1 second

let pollInterval = null;
let isProcessing = false;
let csInterface = null;

function updateStatus(message, className = "") {
    const statusEl = document.getElementById("status");
    if (statusEl) {
        statusEl.textContent = message;
        statusEl.className = `status ${className}`;
    }
}

function log(message) {
    const logEl = document.getElementById("log");
    if (logEl) {
        const time = new Date().toLocaleTimeString();
        const line = document.createElement("div");
        line.textContent = `[${time}] ${message}`;
        logEl.appendChild(line);
        logEl.scrollTop = logEl.scrollHeight;
        
        // Keep only last 20 lines
        while (logEl.children.length > 20) {
            logEl.removeChild(logEl.firstChild);
        }
    }
}

async function pollForJobs() {
    if (isProcessing) {
        return;
    }
    
    try {
        const response = await fetch(`${BRIDGE_URL}/jobs/next`);
        
        if (response.status === 200) {
            const text = await response.text();
            if (!text || text.trim() === '' || text === '{}') {
                updateStatus("Wachten op jobs...", "");
                return;
            }
            
            try {
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
            } catch (parseError) {
                // Empty response or invalid JSON - no jobs available
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
    
    // Try to open project if needed, but don't fail if it doesn't work
    // (project might already be open)
    try {
        await openProject(job.projectPath);
    } catch (error) {
        log(`Waarschuwing bij project openen: ${error.message} - doorgaan met importeren`);
    }
    
    // Ensure bin exists
    log(`Bin aanmaken/vinden: ${job.premiereBinPath}`);
    const bin = await ensureBinPath(job.premiereBinPath);
    
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

function openProject(projectPath) {
    return new Promise((resolve, reject) => {
        // Escape path properly for ExtendScript
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
                    
                    // Check if file exists
                    if (!targetFile.exists) {
                        return JSON.stringify({ success: false, error: "Project file does not exist: " + targetPath });
                    }
                    
                    // Check if project is already open (using app.project.path like watchtower does)
                    var isAlreadyOpen = false;
                    try {
                        if (app.project && app.project.file) {
                            var currentPath = app.project.file.fsName;
                            var targetPathNormalized = targetFile.fsName;
                            
                            // Compare paths (case-insensitive on Mac)
                            if (currentPath.toLowerCase() === targetPathNormalized.toLowerCase()) {
                                isAlreadyOpen = true;
                            }
                        }
                    } catch (checkError) {
                        // If check fails, assume project is not open
                        isAlreadyOpen = false;
                    }
                    
                    // Only open if not already open
                    if (!isAlreadyOpen) {
                        app.openDocument(targetFile);
                        return JSON.stringify({ success: true, message: "Project geopend" });
                    } else {
                        return JSON.stringify({ success: true, message: "Project is al open" });
                    }
                } catch (e) {
                    return JSON.stringify({ success: false, error: e.toString() });
                }
            })();
        `;
        
        csInterface.evalScript(script, (result) => {
            try {
                const parsed = JSON.parse(result);
                if (parsed.success) {
                    resolve(parsed);
                } else {
                    // Don't reject - just log and continue (project might already be open)
                    log(`Waarschuwing: ${parsed.error} - doorgaan met importeren`);
                    resolve({ success: true, message: "Project check gefaald, doorgaan" });
                }
            } catch (e) {
                // Don't reject - just log and continue
                log(`Parse error bij project check: ${e.message} - doorgaan`);
                resolve({ success: true, message: "Project check parse error, doorgaan" });
            }
        });
    });
}

function ensureBinPath(pathString) {
    return new Promise((resolve, reject) => {
        const parts = pathString.split("/").filter(p => p.length > 0);
        
        // Get the last component (e.g., "03_Muziek" from "Oefen project/03_Muziek")
        const lastPart = parts.length > 0 ? parts[parts.length - 1] : pathString;
        
        const script = `
            (function() {
                try {
                    var searchName = ${JSON.stringify(lastPart)};
                    var currentBin = app.project.rootItem;
                    var foundBin = null;
                    
                    // Normalize search name: remove number prefixes (03_, 01_, etc.) and convert to lowercase
                    var normalizeName = function(name) {
                        if (!name || typeof name !== "string") {
                            return "";
                        }
                        var normalized = name.toLowerCase().trim();
                        // Remove number prefix pattern like "03_" or "01_"
                        normalized = normalized.replace(/^\\d+_/, "");
                        return normalized;
                    };
                    
                    var normalizedSearch = normalizeName(searchName);
                    
                    // Music/audio related keywords to search for
                    var musicKeywords = ["muziek", "music", "audio", "sound", "sounds", "sfx", "soundfx"];
                    
                    // Search for existing bin in root that matches music/audio keywords
                    for (var i = 0; i < currentBin.children.numItems; i++) {
                        var child = currentBin.children[i];
                        if (child && child.type === ProjectItemType.BIN && child.name) {
                            var childNameNormalized = normalizeName(child.name);
                            
                            // Check if bin name matches search name (exact or normalized)
                            if (child.name === searchName || 
                                childNameNormalized === normalizedSearch ||
                                childNameNormalized.indexOf(normalizedSearch) !== -1 ||
                                normalizedSearch.indexOf(childNameNormalized) !== -1) {
                                foundBin = child;
                                break;
                            }
                            
                            // Check if bin name contains music keywords
                            for (var k = 0; k < musicKeywords.length; k++) {
                                if (childNameNormalized.indexOf(musicKeywords[k]) !== -1 || 
                                    musicKeywords[k].indexOf(childNameNormalized) !== -1) {
                                    foundBin = child;
                                    break;
                                }
                            }
                            if (foundBin) break;
                        }
                    }
                    
                    // If found, use it; otherwise create/find by exact name
                    if (!foundBin) {
                        // Try to find or create bin with exact name
                        var found = false;
                        for (var j = 0; j < currentBin.children.numItems; j++) {
                            var child = currentBin.children[j];
                            if (child.name === searchName && child.type === ProjectItemType.BIN) {
                                foundBin = child;
                                found = true;
                                break;
                            }
                        }
                        
                        if (!found) {
                            // Create new bin with the search name
                            foundBin = currentBin.createBin(searchName);
                        }
                    }
                    
                    // Build bin path manually
                    var binPathParts = [];
                    var tempBin = foundBin;
                    while (tempBin && tempBin !== app.project.rootItem) {
                        var binName = tempBin.name;
                        if (binName && typeof binName === "string" && binName.length > 0) {
                            binPathParts.unshift(String(binName));
                        } else if (binName) {
                            // If name exists but isn't a string, convert it
                            binPathParts.unshift(String(binName));
                        }
                        tempBin = tempBin.parent;
                    }
                    var binPath = binPathParts.join("/");
                    
                    return JSON.stringify({ success: true, binPath: binPath });
                } catch (e) {
                    return JSON.stringify({ success: false, error: e.toString() });
                }
            })();
        `;
        
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
    });
}

function importFilesIntoBin(files, bin) {
    return new Promise((resolve, reject) => {
        const script = `
            (function() {
                try {
                    var files = ${JSON.stringify(files.map(f => f.replace(/\\/g, "\\\\").replace(/"/g, '\\"')))};
                    var imported = [];
                    var failed = [];
                    var targetBin = app.project.rootItem;
                    
                    // Find bin by path
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
                            if (file.exists) {
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
        
        csInterface.evalScript(script, (result) => {
            try {
                const parsed = JSON.parse(result);
                resolve(parsed);
            } catch (e) {
                reject(e);
            }
        });
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
function initialize() {
    if (typeof CSInterface === 'undefined') {
        setTimeout(initialize, 100);
        return;
    }
    
    csInterface = new CSInterface();
    updateStatus("Starten...", "");
    log("FileFlower Bridge gestart");
    
    // Start polling
    pollInterval = setInterval(pollForJobs, POLL_INTERVAL);
    pollForJobs(); // Immediate first poll
    
    updateStatus("Wachten op jobs...", "");
}

// Wait for DOM and CSInterface
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
} else {
    initialize();
}




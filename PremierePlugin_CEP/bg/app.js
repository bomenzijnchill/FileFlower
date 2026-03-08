// FileFlower Background Service - Draait altijd op de achtergrond
// Start automatisch bij Premiere Pro startup, ook zonder panel open

const BRIDGE_URL = "http://127.0.0.1:17890";
const POLL_INTERVAL = 1000; // 1 second
const ACTIVE_PROJECT_INTERVAL = 2000; // 2 seconds

let pollInterval = null;
let activeProjectInterval = null;
let isProcessing = false;
let csInterface = null;
let lastReportedProject = null;

function log(message) {
    // Log naar console voor debugging
    console.log(`[FileFlower BG] ${new Date().toISOString()}: ${message}`);
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
                return;
            }
            
            try {
                const data = JSON.parse(text);
            
                if (data.projectPath) {
                    isProcessing = true;
                    log(`Job gevonden: ${data.id}`);
                    
                    try {
                        await processJob(data);
                    } catch (error) {
                        log(`Fout bij verwerken: ${error.message}`);
                        await sendResult(data.id, false, [], data.files, error.message);
                    } finally {
                        isProcessing = false;
                    }
                }
            } catch (parseError) {
                // Empty response or invalid JSON - no jobs available
            }
        }
    } catch (error) {
        // Server niet beschikbaar - negeer
    }
}

async function processJob(job) {
    log(`Verwerken project: ${job.projectPath}`);

    // Verifieer dat het juiste project open is voordat we importeren
    const activeProject = await getActiveProjectPath();
    if (activeProject && job.projectPath) {
        const normalizeP = (p) => p.replace(/\/+$/, '').toLowerCase();
        if (normalizeP(activeProject) !== normalizeP(job.projectPath)) {
            log(`Skip job: actief project "${activeProject}" matcht niet met job project "${job.projectPath}"`);
            await sendResult(job.id, false, [], job.files, "Project niet actief");
            return;
        }
    }

    // Import files directly into the correct bin (combined operation)
    log(`Bin pad: "${job.premiereBinPath}"`);
    log(`Importeren van ${job.files.length} bestand(en)`);
    
    let result;
    try {
        result = await ensureBinAndImportFiles(job.premiereBinPath, job.files);
        log(`Import result: success=${result.success}, imported=${result.importedFiles.length}, failed=${result.failedFiles.length}, already=${(result.alreadyImported || []).length}`);
        if (result.error) {
            log(`Import error detail: ${result.error}`);
        }
        if (result.failedFiles.length > 0) {
            log(`Gefaalde bestanden: ${result.failedFiles.join(', ')}`);
        }
        log(`Geïmporteerd in bin: "${result.actualBinPath || "root"}"`);
    } catch (error) {
        log(`Fout bij import (exception): ${error.message}`);
        result = {
            success: false,
            importedFiles: [],
            failedFiles: job.files,
            error: error.message
        };
    }
    
    // Send result
    await sendResult(
        job.id,
        result.success,
        result.importedFiles,
        result.failedFiles,
        result.error,
        result.alreadyImported
    );

    log(`Job voltooid: ${result.importedFiles.length} geïmporteerd, ${(result.alreadyImported || []).length} al aanwezig`);
}

function openProject(projectPath) {
    return new Promise((resolve, reject) => {
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
                    
                    var isAlreadyOpen = false;
                    try {
                        if (app.project && app.project.file) {
                            var currentPath = app.project.file.fsName;
                            var targetPathNormalized = targetFile.fsName;
                            
                            if (currentPath.toLowerCase() === targetPathNormalized.toLowerCase()) {
                                isAlreadyOpen = true;
                            }
                        }
                    } catch (checkError) {
                        isAlreadyOpen = false;
                    }
                    
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
                if (!result || typeof result !== "string") {
                    resolve({ success: true, message: "Invalid result, doorgaan" });
                    return;
                }
                
                var trimmedResult = result.trim();
                if (trimmedResult.startsWith("Error:") || 
                    trimmedResult.startsWith("SyntaxError:") || 
                    trimmedResult.startsWith("ReferenceError:") ||
                    trimmedResult.startsWith("TypeError:") ||
                    trimmedResult.toLowerCase().indexOf("evalscript error") !== -1) {
                    resolve({ success: true, message: "ExtendScript error, doorgaan" });
                    return;
                }
                
                const parsed = JSON.parse(result);
                resolve(parsed);
            } catch (e) {
                resolve({ success: true, message: "Parse error, doorgaan" });
            }
        });
    });
}

/**
 * Combined function: finds/creates bin AND imports files in one ExtendScript call.
 * This ensures the bin reference is used directly for import, avoiding the mismatch
 * between fuzzy-matched bin names and exact lookup.
 */
function ensureBinAndImportFiles(pathString, files) {
    return new Promise((resolve, reject) => {
        const parts = pathString.split("/").filter(p => p.length > 0);
        const escapedFiles = files.map(f => f.replace(/\\/g, "\\\\").replace(/"/g, '\\"'));
        
        const script = `
            (function() {
                try {
                    if (!app.project) {
                        return JSON.stringify({ 
                            success: false, 
                            importedFiles: [], 
                            failedFiles: ${JSON.stringify(escapedFiles)},
                            error: "No project is open",
                            actualBinPath: ""
                        });
                    }
                    
                    var pathParts = ${JSON.stringify(parts)};
                    var filesToImport = ${JSON.stringify(escapedFiles)};
                    var rootBin = app.project.rootItem;
                    var currentBin = rootBin;
                    
                    // Normalize function for fuzzy matching
                    var normalize = function(name) {
                        if (!name || typeof name !== "string") return "";
                        var n = name.toLowerCase();
                        var whitespace = " \\t\\n\\r";
                        while (n.length > 0 && whitespace.indexOf(n.charAt(0)) !== -1) {
                            n = n.substring(1);
                        }
                        while (n.length > 0 && whitespace.indexOf(n.charAt(n.length - 1)) !== -1) {
                            n = n.substring(0, n.length - 1);
                        }
                        // Remove leading numbers like "03_" or "04_"
                        if (n.match(/^\\d+[_\\-\\s]/)) {
                            n = n.replace(/^\\d+[_\\-\\s]+/, "");
                        }
                        return n;
                    };
                    
                    // Find or create bin with fuzzy matching
                    var findOrCreateBin = function(parentBin, searchName) {
                        var normalizedSearch = normalize(searchName);
                        
                        // First: exact match
                        for (var i = 0; i < parentBin.children.numItems; i++) {
                            var child = parentBin.children[i];
                            if (child && child.type === ProjectItemType.BIN) {
                                var childName = String(child.name || "");
                                if (childName === searchName) {
                                    return child;
                                }
                            }
                        }
                        
                        // Second: normalized match
                        for (var j = 0; j < parentBin.children.numItems; j++) {
                            var child = parentBin.children[j];
                            if (child && child.type === ProjectItemType.BIN) {
                                var childName = String(child.name || "");
                                var normalizedChild = normalize(childName);
                                
                                if (normalizedChild === normalizedSearch || 
                                    normalizedChild.indexOf(normalizedSearch) !== -1 ||
                                    normalizedSearch.indexOf(normalizedChild) !== -1) {
                                    return child;
                                }
                            }
                        }
                        
                        // Not found: create new bin
                        return parentBin.createBin(searchName);
                    };
                    
                    var musicKeywords = ["muziek", "music", "audio"];
                    var sfxKeywords = ["sfx", "soundfx", "sound effects", "geluidseffecten"];
                    
                    // Navigate/create the bin path
                    for (var p = 0; p < pathParts.length; p++) {
                        var partName = String(pathParts[p]);
                        
                        if (p === 0) {
                            // First level: use keyword matching for Music/SFX folders
                            var foundFirst = null;
                            var normalizedPart = normalize(partName);
                            
                            var isMusicSearch = false;
                            var isSfxSearch = false;
                            for (var mk = 0; mk < musicKeywords.length; mk++) {
                                if (normalizedPart.indexOf(musicKeywords[mk]) !== -1) {
                                    isMusicSearch = true;
                                    break;
                                }
                            }
                            for (var sk = 0; sk < sfxKeywords.length; sk++) {
                                if (normalizedPart.indexOf(sfxKeywords[sk]) !== -1) {
                                    isSfxSearch = true;
                                    break;
                                }
                            }
                            
                            for (var i = 0; i < currentBin.children.numItems; i++) {
                                var child = currentBin.children[i];
                                if (child && child.type === ProjectItemType.BIN) {
                                    var childName = String(child.name || "");
                                    var normalizedChild = normalize(childName);
                                    
                                    // Exact match
                                    if (childName === partName) {
                                        foundFirst = child;
                                        break;
                                    }
                                    
                                    // Normalized match
                                    if (normalizedChild === normalizedPart) {
                                        foundFirst = child;
                                        break;
                                    }
                                    
                                    // Keyword match for music
                                    if (isMusicSearch) {
                                        for (var mk2 = 0; mk2 < musicKeywords.length; mk2++) {
                                            if (normalizedChild.indexOf(musicKeywords[mk2]) !== -1) {
                                                foundFirst = child;
                                                break;
                                            }
                                        }
                                    }
                                    // Keyword match for SFX
                                    if (isSfxSearch && !foundFirst) {
                                        for (var sk2 = 0; sk2 < sfxKeywords.length; sk2++) {
                                            if (normalizedChild.indexOf(sfxKeywords[sk2]) !== -1) {
                                                foundFirst = child;
                                                break;
                                            }
                                        }
                                    }
                                    if (foundFirst) break;
                                }
                            }
                            
                            if (foundFirst) {
                                currentBin = foundFirst;
                            } else {
                                currentBin = currentBin.createBin(partName);
                            }
                        } else {
                            // Subsequent levels: use findOrCreateBin
                            currentBin = findOrCreateBin(currentBin, partName);
                        }
                    }
                    
                    // Build actual bin path for logging
                    var binPathParts = [];
                    var tempBin = currentBin;
                    while (tempBin && tempBin !== rootBin) {
                        var binName = tempBin.name;
                        if (binName && typeof binName === "string" && binName.length > 0) {
                            binPathParts.unshift(String(binName));
                        }
                        tempBin = tempBin.parent;
                    }
                    var actualBinPath = binPathParts.join("/");
                    
                    // Collect existing media paths in this bin to avoid duplicate imports
                    var existingPaths = {};
                    for (var e = 0; e < currentBin.children.numItems; e++) {
                        var existingChild = currentBin.children[e];
                        if (existingChild) {
                            try {
                                var mediaPath = existingChild.getMediaPath();
                                if (mediaPath && typeof mediaPath === "string" && mediaPath.length > 0) {
                                    existingPaths[mediaPath.toLowerCase()] = true;
                                }
                            } catch (mpErr) {
                                // getMediaPath() kan falen voor bins of items zonder media
                            }
                        }
                    }

                    // NOW import files directly into currentBin (we have the reference!)
                    var imported = [];
                    var failed = [];
                    var alreadyImported = [];

                    // Use currentBin directly for import target
                    var targetBin = currentBin;
                    if (!targetBin || (targetBin.type !== ProjectItemType.BIN && targetBin.type !== ProjectItemType.ROOT)) {
                        targetBin = rootBin;
                    }

                    // Collect all valid file paths for batch import
                    var validPaths = [];
                    var validPathMap = {}; // maps index in validPaths to original filePath

                    for (var f = 0; f < filesToImport.length; f++) {
                        var filePath = filesToImport[f];

                        // Check of dit bestand al in de bin zit
                        if (existingPaths[filePath.toLowerCase()] === true) {
                            alreadyImported.push(filePath);
                            continue;
                        }

                        var file = new File(filePath);
                        if (file.exists) {
                            validPaths.push(filePath);
                            validPathMap[validPaths.length - 1] = filePath;
                        } else {
                            failed.push(filePath);
                        }
                    }

                    // Batch import all files at once
                    if (validPaths.length > 0) {
                        try {
                            var importResult = app.project.importFiles(validPaths, false, targetBin, false);
                            // If we get here without error, all files were imported
                            for (var v = 0; v < validPaths.length; v++) {
                                imported.push(validPaths[v]);
                            }
                        } catch (batchError) {
                            // Batch failed, try one by one
                            for (var s = 0; s < validPaths.length; s++) {
                                try {
                                    app.project.importFiles([validPaths[s]], false, targetBin, false);
                                    imported.push(validPaths[s]);
                                } catch (singleError) {
                                    failed.push(validPaths[s]);
                                }
                            }
                        }
                    }

                    return JSON.stringify({
                        success: failed.length === 0,
                        importedFiles: imported,
                        failedFiles: failed,
                        alreadyImported: alreadyImported,
                        actualBinPath: actualBinPath
                    });
                } catch (e) {
                    return JSON.stringify({
                        success: false,
                        importedFiles: [],
                        failedFiles: ${JSON.stringify(escapedFiles)},
                        error: e.toString(),
                        actualBinPath: ""
                    });
                }
            })();
        `;
        
        csInterface.evalScript(script, (result) => {
            try {
                if (!result || typeof result !== "string") {
                    reject(new Error("Invalid result from ExtendScript"));
                    return;
                }
                
                var trimmedResult = result.trim();
                if (trimmedResult.startsWith("Error:") || 
                    trimmedResult.startsWith("SyntaxError:") || 
                    trimmedResult.startsWith("ReferenceError:") ||
                    trimmedResult.startsWith("TypeError:") ||
                    trimmedResult.toLowerCase().indexOf("evalscript error") !== -1) {
                    reject(new Error("ExtendScript error: " + trimmedResult));
                    return;
                }
                
                const parsed = JSON.parse(result);
                resolve(parsed);
            } catch (e) {
                reject(new Error("JSON parse error: " + e.message));
            }
        });
    });
}

async function sendResult(jobId, success, importedFiles, failedFiles, error, alreadyImported) {
    try {
        const result = {
            jobId: jobId,
            success: success,
            importedFiles: importedFiles || [],
            failedFiles: failedFiles || [],
            error: error || null,
            alreadyImported: alreadyImported || []
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

function getActiveProjectPath() {
    return new Promise((resolve) => {
        const script = `
            (function() {
                try {
                    if (app.project && app.project.path) {
                        return app.project.path;
                    } else if (app.project && app.project.file) {
                        return app.project.file.fsName;
                    }
                    return "";
                } catch (e) {
                    return "";
                }
            })();
        `;

        csInterface.evalScript(script, (result) => {
            if (result && typeof result === "string" && result.trim().length > 0) {
                resolve(result.trim());
            } else {
                resolve(null);
            }
        });
    });
}

async function reportActiveProject() {
    return new Promise((resolve) => {
        const script = `
            (function() {
                try {
                    if (app.project && app.project.path) {
                        return JSON.stringify({
                            projectPath: app.project.path,
                            projectName: app.project.name
                        });
                    } else if (app.project && app.project.file) {
                        return JSON.stringify({
                            projectPath: app.project.file.fsName,
                            projectName: app.project.name
                        });
                    } else {
                        return JSON.stringify({ projectPath: null });
                    }
                } catch (e) {
                    return JSON.stringify({ projectPath: null, error: e.toString() });
                }
            })();
        `;
        
        csInterface.evalScript(script, async (result) => {
            try {
                if (!result || typeof result !== "string") {
                    resolve(null);
                    return;
                }
                
                const parsed = JSON.parse(result);
                const currentProject = parsed.projectPath;

                // Altijd rapporteren (niet alleen bij change) zodat de server
                // freshness timestamp wordt bijgewerkt (server eist <10s fresh)
                try {
                    await fetch(`${BRIDGE_URL}/active-project`, {
                        method: "POST",
                        headers: {
                            "Content-Type": "application/json"
                        },
                        body: JSON.stringify({ projectPath: currentProject })
                    });

                    if (currentProject && currentProject !== lastReportedProject) {
                        log(`Actief project: ${parsed.projectName || currentProject}`);
                        lastReportedProject = currentProject;
                    }
                } catch (fetchError) {
                    // Server niet beschikbaar
                }
                
                resolve(currentProject);
            } catch (e) {
                resolve(null);
            }
        });
    });
}

// Initialize background service
function initialize() {
    if (typeof CSInterface === 'undefined') {
        setTimeout(initialize, 100);
        return;
    }
    
    csInterface = new CSInterface();
    log("FileFlower Background Service gestart");
    
    // Start polling voor jobs
    pollInterval = setInterval(pollForJobs, POLL_INTERVAL);
    pollForJobs();
    
    // Start rapporteren van actief project
    activeProjectInterval = setInterval(reportActiveProject, ACTIVE_PROJECT_INTERVAL);
    reportActiveProject();
    
    log("Background polling actief");
}

// Start when ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
} else {
    initialize();
}




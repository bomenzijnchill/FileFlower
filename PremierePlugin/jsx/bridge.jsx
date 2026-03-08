// ExtendScript bridge for Premiere Pro API calls
// This file provides helper functions for the UXP plugin

function openProject(projectPath) {
    try {
        var projectFile = new File(projectPath);
        
        // Check if project is already open
        if (app.project.file && app.project.file.fsName === projectFile.fsName) {
            return {
                success: true,
                message: "Project is already open"
            };
        }
        
        // Open the project
        app.openDocument(projectFile);
        
        return {
            success: true,
            message: "Project opened successfully"
        };
    } catch (e) {
        return {
            success: false,
            error: e.toString()
        };
    }
}

function ensureBinPath(pathString) {
    try {
        var parts = pathString.split("/").filter(function(p) { return p.length > 0; });
        
        // Get the last component (e.g., "03_Muziek" from "Oefen project/03_Muziek")
        var searchName = parts.length > 0 ? parts[parts.length - 1] : pathString;
        var currentBin = app.project.rootItem;
        var foundBin = null;
        
        // Ensure searchName is a string
        if (typeof searchName !== "string") {
            searchName = String(searchName || "");
        }
        
        // Normalize search name: remove number prefixes (03_, 01_, etc.) and convert to lowercase
        var normalizeName = function(name) {
            try {
                if (!name) {
                    return "";
                }
                
                // Convert to string - try multiple methods
                var nameStr = null;
                
                // Method 1: Check if already string
                if (typeof name === "string") {
                    nameStr = name;
                }
                // Method 2: Try toString() if available
                else if (name && typeof name.toString === "function") {
                    try {
                        var str = name.toString();
                        if (typeof str === "string") {
                            nameStr = str;
                        }
                    } catch (e) {
                        // toString failed, try next method
                    }
                }
                
                // Method 3: Use String() constructor
                if (!nameStr) {
                    try {
                        nameStr = String(name);
                        if (typeof nameStr !== "string") {
                            return "";
                        }
                    } catch (e) {
                        return "";
                    }
                }
                
                // Final check
                if (!nameStr || typeof nameStr !== "string" || nameStr === "undefined" || nameStr === "null") {
                    return "";
                }
                
                // Now safely use string methods - trim whitespace manually
                var trimmed = nameStr;
                var whitespace = " \t\n\r";
                while (trimmed.length > 0 && whitespace.indexOf(trimmed.charAt(0)) !== -1) {
                    trimmed = trimmed.substring(1);
                }
                while (trimmed.length > 0 && whitespace.indexOf(trimmed.charAt(trimmed.length - 1)) !== -1) {
                    trimmed = trimmed.substring(0, trimmed.length - 1);
                }
                
                // Convert to lowercase
                var normalized = trimmed.toLowerCase();
                
                // Remove number prefix pattern like "03_" or "01_"
                if (normalized.match(/^\d+_/)) {
                    normalized = normalized.replace(/^\d+_/, "");
                }
                
                return normalized;
            } catch (e) {
                return "";
            }
        };
        
        var normalizedSearch = normalizeName(searchName);
        
        // Music/audio related keywords to search for
        var musicKeywords = ["muziek", "music", "audio", "sound", "sounds", "sfx", "soundfx"];
        
        // Search for existing bin in root that matches music/audio keywords
        for (var i = 0; i < currentBin.children.numItems; i++) {
            var child = currentBin.children[i];
            if (child && child.type === ProjectItemType.BIN) {
                // Convert child.name to string explicitly
                var childName = child.name ? String(child.name) : "";
                if (!childName) continue;
                
                var childNameNormalized = normalizeName(childName);
                
                // Check if bin name matches search name (exact or normalized)
                if (childName === searchName || 
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
                if (child && child.type === ProjectItemType.BIN) {
                    var childName = child.name ? String(child.name) : "";
                    if (childName === searchName) {
                        foundBin = child;
                        found = true;
                        break;
                    }
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
        while (tempBin && tempBin !== app.project.rootItem && tempBin.name) {
            binPathParts.unshift(tempBin.name);
            tempBin = tempBin.parent;
        }
        var binPath = binPathParts.join("/");
        
        return {
            success: true,
            binPath: binPath
        };
    } catch (e) {
        return {
            success: false,
            error: e.toString()
        };
    }
}

function importFilesIntoBin(files, binPath) {
    try {
        var importedFiles = [];
        var failedFiles = [];
        
        // Find bin by path
        var bin = app.project.rootItem;
        var parts = binPath.split("/").filter(function(p) { return p.length > 0; });
        
        for (var i = 0; i < parts.length; i++) {
            var part = parts[i];
            var found = false;
            
            for (var j = 0; j < bin.children.numItems; j++) {
                var child = bin.children[j];
                if (child.name === part && child.type === ProjectItemType.BIN) {
                    bin = child;
                    found = true;
                    break;
                }
            }
            
            if (!found) {
                return {
                    success: false,
                    error: "Bin not found: " + binPath,
                    importedFiles: [],
                    failedFiles: files
                };
            }
        }
        
        // Import files
        for (var k = 0; k < files.length; k++) {
            try {
                var file = new File(files[k]);
                if (file.exists) {
                    app.project.importFiles([file.fsName], false, bin, 0);
                    importedFiles.push(files[k]);
                } else {
                    failedFiles.push(files[k]);
                }
            } catch (e) {
                failedFiles.push(files[k]);
            }
        }
        
        return {
            success: failedFiles.length === 0,
            importedFiles: importedFiles,
            failedFiles: failedFiles
        };
    } catch (e) {
        return {
            success: false,
            error: e.toString(),
            importedFiles: [],
            failedFiles: files
        };
    }
}



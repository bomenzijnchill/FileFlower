// FileFlower CEP Panel - Optionele UI voor status weergave
// De echte werk wordt gedaan door de background service (bg/app.js)
// Dit panel is optioneel - de plugin werkt ook zonder dit panel open te hebben

const BRIDGE_URL = "http://127.0.0.1:17890";
const STATUS_CHECK_INTERVAL = 2000;

let statusInterval = null;
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

async function checkServerStatus() {
    try {
        const response = await fetch(`${BRIDGE_URL}/status`);
        
        if (response.ok) {
            updateStatus("✅ Verbonden met macOS app", "connected");
        } else {
            updateStatus("⚠️ Server antwoordt niet correct", "error");
        }
    } catch (error) {
        updateStatus("❌ Geen verbinding met macOS app", "error");
    }
}

async function checkActiveProject() {
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
        
        csInterface.evalScript(script, (result) => {
            try {
                if (!result || typeof result !== "string") {
                    resolve(null);
                    return;
                }
                
                const parsed = JSON.parse(result);
                const projectInfo = document.getElementById("projectInfo");
                if (projectInfo) {
                    if (parsed.projectPath) {
                        projectInfo.textContent = `📁 ${parsed.projectName || parsed.projectPath}`;
                    } else {
                        projectInfo.textContent = "Geen project geopend";
                    }
                }
                resolve(parsed.projectPath);
            } catch (e) {
                resolve(null);
            }
        });
    });
}

// Initialize
function initialize() {
    if (typeof CSInterface === 'undefined') {
        setTimeout(initialize, 100);
        return;
    }
    
    csInterface = new CSInterface();
    updateStatus("Initialiseren...", "");
    log("FileFlower Panel gestart");
    log("📌 Background service draait automatisch");
    log("Dit panel is optioneel voor status");
    
    // Check server status periodically
    statusInterval = setInterval(() => {
        checkServerStatus();
        checkActiveProject();
    }, STATUS_CHECK_INTERVAL);
    
    // Initial checks
    checkServerStatus();
    checkActiveProject();
}

// Wait for DOM and CSInterface
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
} else {
    initialize();
}

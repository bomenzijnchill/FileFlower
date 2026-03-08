// DLtoPremiere CEP - ExtendScript bridge
// This file runs in Premiere's ExtendScript engine

/**
 * Debug logging function
 */
function debugLog(message) {
    try {
        var timestamp = new Date().toISOString();
        var logMessage = timestamp + ": " + message + "\n";
        $.writeln(logMessage.trim());
    } catch (error) {
        $.writeln("Debug log error: " + error.toString());
    }
}

debugLog("DLtoPremiere ExtendScript bridge loaded");


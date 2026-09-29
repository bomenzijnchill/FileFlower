// DLtoPremiere CEP - ExtendScript bridge
// This file runs in Premiere's ExtendScript engine

// JSON-polyfill: Premiere 26 levert geen JSON-object meer in zijn
// ExtendScript-omgeving, waardoor elk script met JSON.stringify afbreekt met
// "EvalScript error.". Alleen definiëren als hij ontbreekt; stringify dekt wat
// de plugin teruggeeft (strings, getallen, booleans, null, arrays en platte
// objecten).
if (typeof JSON === "undefined") {
    JSON = {};
}
if (typeof JSON.stringify !== "function") {
    JSON.stringify = function (value) {
        function esc(s) {
            return '"' + String(s)
                .replace(/\\/g, "\\\\")
                .replace(/"/g, '\\"')
                .replace(/\n/g, "\\n")
                .replace(/\r/g, "\\r")
                .replace(/\t/g, "\\t")
                .replace(/[\u0000-\u001f]/g, function (c) {
                    var hex = c.charCodeAt(0).toString(16);
                    return "\\u0000".slice(0, 6 - hex.length) + hex;
                }) + '"';
        }
        function go(v) {
            var i, k, out;
            if (v === null || v === undefined) { return "null"; }
            if (typeof v === "number") { return isFinite(v) ? String(v) : "null"; }
            if (typeof v === "boolean") { return String(v); }
            if (typeof v === "string") { return esc(v); }
            if (v instanceof Array) {
                out = [];
                for (i = 0; i < v.length; i++) { out.push(go(v[i])); }
                return "[" + out.join(",") + "]";
            }
            if (typeof v === "object") {
                out = [];
                for (k in v) {
                    if (v.hasOwnProperty(k)) { out.push(esc(k) + ":" + go(v[k])); }
                }
                return "{" + out.join(",") + "}";
            }
            return "null";
        }
        return go(value);
    };
}
if (typeof JSON.parse !== "function") {
    JSON.parse = function (text) {
        // ExtendScript-eval; de input komt uit de eigen scripts, niet van buiten.
        return eval("(" + text + ")");
    };
}

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


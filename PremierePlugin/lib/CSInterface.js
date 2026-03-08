/**
 * CSInterface.js
 * 
 * Adobe UXP CSInterface stub for Premiere Pro
 * In a real implementation, this would be provided by Adobe's CEP/UXP runtime
 * This is a minimal stub for development/testing
 */

if (typeof CSInterface === 'undefined') {
    function CSInterface() {
        this.getHostEnvironment = function() {
            return {
                evaluateScript: function(script, callback) {
                    // Stub implementation
                    // In real UXP, this would call ExtendScript
                    console.warn('CSInterface stub: evaluateScript called');
                    if (callback) {
                        callback('{"success":false,"error":"CSInterface stub - not implemented"}');
                    }
                }
            };
        };
        
        this.evalScript = function(script, callback) {
            // Stub implementation
            console.warn('CSInterface stub: evalScript called');
            if (callback) {
                callback('{"success":false,"error":"CSInterface stub - not implemented"}');
            }
        };
    }
    
    // Export for use
    if (typeof module !== 'undefined' && module.exports) {
        module.exports = CSInterface;
    }
}


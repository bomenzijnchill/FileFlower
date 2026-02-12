import Foundation
import IOKit

class ThermalManager {
    static let shared = ThermalManager()
    
    private let maxGPUTemperature: Double = 80.0 // Celsius
    private let throttleTemperature: Double = 75.0 // Start throttling hier
    private let checkInterval: TimeInterval = 2.0 // Check elke 2 seconden
    
    private var lastCheckTime: Date = Date()
    private var lastGPUTemperature: Double = 0.0
    private var isThrottling: Bool = false
    
    private init() {}
    
    /// Haal de huidige GPU temperatuur op (indien beschikbaar)
    func getGPUTemperature() -> Double? {
        // Op macOS kunnen we GPU temperatuur ophalen via IOKit
        // Dit is een vereenvoudigde implementatie
        // Voor productie zou je een meer robuuste implementatie willen
        
        // Apple Silicon Macs hebben geen directe GPU temperatuur sensor
        // We gebruiken CPU temperatuur als proxy, of schatten op basis van workload
        // Voor nu retourneren we nil en gebruiken we rate limiting als alternatief
        
        // TODO: Implementeer betere temperatuur monitoring indien mogelijk
        return nil
    }
    
    /// Check of we kunnen verwerken zonder overheating
    func canProcess() -> Bool {
        let now = Date()
        
        // Rate limiting: max 1 classificatie per seconde als we throttlen
        if isThrottling {
            if now.timeIntervalSince(lastCheckTime) < 1.0 {
                return false
            }
        }
        
        lastCheckTime = now
        
        // Check temperatuur indien beschikbaar
        if let temp = getGPUTemperature() {
            lastGPUTemperature = temp
            
            if temp >= maxGPUTemperature {
                isThrottling = true
                return false
            } else if temp >= throttleTemperature {
                isThrottling = true
                // Allow maar met delay
                return now.timeIntervalSince(lastCheckTime) >= 2.0
            } else {
                isThrottling = false
            }
        }
        
        return true
    }
    
    /// Wacht tot we kunnen verwerken (met timeout)
    func waitUntilCanProcess(timeout: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()
        
        while !canProcess() {
            if Date().timeIntervalSince(startTime) > timeout {
                return false
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconden
        }
        
        return true
    }
    
    /// Reset throttling status
    func reset() {
        isThrottling = false
        lastCheckTime = Date()
    }
    
    /// Check of we momenteel throttlen
    var isCurrentlyThrottling: Bool {
        return isThrottling
    }
}


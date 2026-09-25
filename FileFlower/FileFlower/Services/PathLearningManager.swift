import Foundation

class PathLearningManager {
    static let shared = PathLearningManager()

    private init() {}

    /// Sla een padkeuze op zodat de app ervan leert.
    /// Wordt aangeroepen bij: handmatige path edit, path confirmation, en na backwards reasoning scan.
    func recordPathDecision(
        projectPath: String,
        assetType: AssetType,
        subfolder: String?,
        chosenPath: String,
        fileExtension: String,
        source: DetectedSource?,
        isScanned: Bool = false
    ) {
        let appState = AppState.shared
        var config = appState.config

        let mappingKey = projectPath
        var mapping = config.mappings[mappingKey] ?? ProjectMapping()
        var structure = mapping.discoveredStructure ?? DiscoveredProjectStructure(
            discoveredPaths: [:],
            namingConvention: nil,
            lastScannedDate: Date()
        )

        var rules = structure.learnedRules ?? []

        // Zoek bestaande regel met zelfde combinatie
        if let existingIndex = rules.firstIndex(where: { rule in
            rule.assetType == assetType.rawValue &&
            rule.subfolder == subfolder &&
            rule.source == source?.rawValue &&
            rule.isScanned == isScanned
        }) {
            // Verhoog usage count en update pad als het verschilt
            var existing = rules[existingIndex]
            existing.usageCount += 1
            if !existing.fileExtensions.contains(fileExtension) {
                let updated = LearnedPathRule(
                    assetType: existing.assetType,
                    subfolder: existing.subfolder,
                    resolvedPath: chosenPath,
                    fileExtensions: existing.fileExtensions + [fileExtension],
                    source: existing.source,
                    learnedAt: existing.learnedAt,
                    usageCount: existing.usageCount,
                    isScanned: existing.isScanned
                )
                rules[existingIndex] = updated
            } else {
                rules[existingIndex] = LearnedPathRule(
                    assetType: existing.assetType,
                    subfolder: existing.subfolder,
                    resolvedPath: chosenPath,
                    fileExtensions: existing.fileExtensions,
                    source: existing.source,
                    learnedAt: existing.learnedAt,
                    usageCount: existing.usageCount,
                    isScanned: existing.isScanned
                )
            }
        } else {
            // Nieuwe regel
            let rule = LearnedPathRule(
                assetType: assetType.rawValue,
                subfolder: subfolder,
                resolvedPath: chosenPath,
                fileExtensions: [fileExtension],
                source: source?.rawValue,
                learnedAt: Date(),
                usageCount: 1,
                isScanned: isScanned
            )
            rules.append(rule)
        }

        // Prune: max 100 regels per project
        if rules.count > 100 {
            rules.sort { $0.usageCount > $1.usageCount }
            rules = Array(rules.prefix(100))
        }

        structure.learnedRules = rules
        mapping.discoveredStructure = structure
        config.mappings[mappingKey] = mapping

        appState.config = config
        ConfigManager.shared.save(config)

        #if DEBUG
        print("PathLearning: Regel opgeslagen - \(assetType.rawValue)/\(subfolder ?? "none") → \(chosenPath)")
        #endif
    }

    /// Zoek de best matchende geleerde regel voor een gegeven combinatie.
    /// Priority: handmatig > gescand, specifiek > generiek.
    func findMatchingRule(
        projectPath: String,
        assetType: AssetType,
        subfolder: String?,
        source: DetectedSource?
    ) -> LearnedPathRule? {
        let config = AppState.shared.config
        guard let mapping = config.mappings[projectPath],
              let structure = mapping.discoveredStructure,
              let rules = structure.learnedRules else {
            return nil
        }

        // Score elke regel op relevantie
        var candidates: [(rule: LearnedPathRule, score: Int)] = []

        for rule in rules where rule.assetType == assetType.rawValue {
            var score = 0

            // Subfolder match
            if rule.subfolder == subfolder {
                score += 4
            } else if rule.subfolder == nil && subfolder == nil {
                score += 4
            } else if rule.subfolder != nil && subfolder != nil {
                continue // Subfolder mismatch, skip
            }

            // Source match
            if rule.source == source?.rawValue {
                score += 2
            }

            // Handmatig geleerd > gescand
            if !rule.isScanned {
                score += 3
            }

            // Usage count bonus
            score += min(rule.usageCount, 5)

            candidates.append((rule, score))
        }

        // Sorteer op score (hoog → laag)
        candidates.sort { $0.score > $1.score }

        return candidates.first?.rule
    }

    /// Migratie: verwijder geleerde regels met absolute paden (legacy bug).
    /// Dergelijke regels veroorzaakten geneste folder-structuren bij gebruik.
    /// Muteert de gegeven config; returnt aantal verwijderde regels.
    static func removeBadAbsolutePathRules(in config: inout Config) -> Int {
        var totalRemoved = 0
        for (mappingKey, mapping) in config.mappings {
            guard var structure = mapping.discoveredStructure,
                  let rules = structure.learnedRules else { continue }

            let cleaned = rules.filter { !$0.resolvedPath.hasPrefix("/") }
            let removed = rules.count - cleaned.count
            if removed > 0 {
                totalRemoved += removed
                structure.learnedRules = cleaned
                var updated = mapping
                updated.discoveredStructure = structure
                config.mappings[mappingKey] = updated
                #if DEBUG
                print("PathLearning migration: \(removed) bad rule(s) removed from \(mappingKey)")
                #endif
            }
        }
        return totalRemoved
    }

    /// Verwijder alle gescande regels voor een project (bij re-analyse).
    func clearScannedRules(for projectPath: String) {
        let appState = AppState.shared
        var config = appState.config

        guard var mapping = config.mappings[projectPath],
              var structure = mapping.discoveredStructure,
              var rules = structure.learnedRules else {
            return
        }

        rules.removeAll { $0.isScanned }
        structure.learnedRules = rules
        mapping.discoveredStructure = structure
        config.mappings[projectPath] = mapping

        appState.config = config
        ConfigManager.shared.save(config)
    }
}

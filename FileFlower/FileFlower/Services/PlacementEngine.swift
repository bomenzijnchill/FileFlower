import Foundation

/// Beschrijft wat we zoeken: welk soort bestand willen we plaatsen?
/// Bewust gedefinieerd op primitieven (geen AssetType/Config dependencies)
/// zodat de engine puur en los testbaar is.
struct PlacementQuery {
    /// Bestandsnaam van het te plaatsen bestand (bv. "ES_Higher (Instrumental Version) - Siine.wav")
    let fileName: String
    /// Extensies die als "hetzelfde soort bestand" tellen (lowercase, bv. audio-extensies voor muziek)
    let peerExtensions: Set<String>
    /// Mapnaam-keywords die bij dit asset type horen (genormaliseerd, bv. ["music", "muziek", "audio"])
    let keywords: [String]
    /// Mapnaam-keywords die juist NIET bij dit type horen (bv. ["sfx", "vo"] voor muziek)
    let avoidKeywords: [String]
    /// Optionele verfijning (mood/genre/categorie)
    let subfolder: String?
}

/// Eén kandidaat-bestemming met bewijs.
struct PlacementCandidate {
    let directoryURL: URL
    /// Relatief pad t.o.v. de project-hoofdmap
    let relativePath: String
    /// Genormaliseerde score (hoger = sterker bewijs)
    let score: Double
    /// Aantal vergelijkbare bestanden dat al in deze map staat
    let peerCount: Int
    /// Aantal bestanden met dezelfde naamprefix (bv. "ES_")
    let prefixCount: Int
    /// Menselijk leesbare uitleg
    let reason: String
}

/// Momentopname van één map in de projectboom (voor hergebruik over meerdere queries).
struct PlacementDirEntry {
    let url: URL
    let relativePath: String
    let depth: Int
    /// (bestandsnaam, extensie lowercase, laatst gewijzigd)
    let files: [(name: String, ext: String, modified: Date?)]
}

/// Evidence-gebaseerde plaatsing: doorzoekt de bestaande projectstructuur en
/// beoordeelt waar vergelijkbare bestanden ál staan. Puur lezend — maakt nooit
/// mappen aan en heeft geen afhankelijkheid van app-state.
final class PlacementEngine {

    /// Maximale zoekdiepte vanaf de project-hoofdmap.
    private let maxDepth: Int
    /// Minimum aantal peers voordat een map als bewijs telt.
    private let minPeerCount: Int

    init(maxDepth: Int = 6, minPeerCount: Int = 2) {
        self.maxDepth = maxDepth
        self.minPeerCount = minPeerCount
    }

    // MARK: - Snapshot (één filesystem-walk, herbruikbaar over queries)

    /// Maak een snapshot van de projectboom. Duur op netwerkschijven — cache dit
    /// per projectroot en evalueer meerdere queries tegen dezelfde snapshot.
    func snapshot(projectRoot: URL) -> [PlacementDirEntry] {
        var entries: [PlacementDirEntry] = []
        walkSnapshot(directory: projectRoot, root: projectRoot, depth: 0, into: &entries)
        return entries
    }

    private func walkSnapshot(directory: URL, root: URL, depth: Int, into entries: inout [PlacementDirEntry]) {
        guard depth <= maxDepth else { return }
        // Cache/systeem-mappen: nooit in kijken, nooit als kandidaat
        if depth > 0 && PathSafetyPolicy.isBlockedFolderName(directory.lastPathComponent) { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [(name: String, ext: String, modified: Date?)] = []
        var subdirs: [URL] = []

        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                subdirs.append(item)
            } else {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                files.append((item.lastPathComponent, item.pathExtension.lowercased(), modified))
            }
        }

        // De projectroot zelf (depth 0) is nooit een plaatsingskandidaat:
        // losse bestanden in de root zijn geen bewijs van een bewuste structuur.
        if depth > 0 {
            entries.append(PlacementDirEntry(
                url: directory,
                relativePath: Self.relative(directory, to: root),
                depth: depth,
                files: files
            ))
        }

        for subdir in subdirs {
            walkSnapshot(directory: subdir, root: root, depth: depth + 1, into: &entries)
        }
    }

    // MARK: - Kandidaten

    /// Vind kandidaat-bestemmingen voor een bestand, gesorteerd op score (via verse snapshot).
    func findCandidates(projectRoot: URL, query: PlacementQuery) -> [PlacementCandidate] {
        return findCandidates(snapshot: snapshot(projectRoot: projectRoot), query: query)
    }

    /// Vind kandidaat-bestemmingen binnen een eerder gemaakte snapshot.
    func findCandidates(snapshot: [PlacementDirEntry], query: PlacementQuery) -> [PlacementCandidate] {
        var candidates: [PlacementCandidate] = []
        let filePrefix = Self.namePrefix(of: query.fileName)

        for entry in snapshot {
            var peerCount = 0
            var prefixCount = 0
            var newestPeerDate: Date?

            for file in entry.files where query.peerExtensions.contains(file.ext) {
                peerCount += 1
                if let prefix = filePrefix, file.name.hasPrefix(prefix) {
                    prefixCount += 1
                }
                if let modified = file.modified {
                    if newestPeerDate == nil || modified > newestPeerDate! {
                        newestPeerDate = modified
                    }
                }
            }

            guard peerCount >= minPeerCount else { continue }

            let components = entry.relativePath.split(separator: "/").map(String.init)

            // Avoid-check: token-gebaseerd (minstens zo sterk als de keyword-check).
            // Een avoid-hit op de EIGEN mapnaam (laatste component) diskwalificeert hard —
            // "Sound Effects" mag nooit muziek-kandidaat zijn, ook al heet de parent "03_Audio".
            var avoidOnParent = false
            var avoidOnSelf = false
            for (index, component) in components.enumerated() {
                if Self.matchesAny(component, keywords: query.avoidKeywords) {
                    if index == components.count - 1 {
                        avoidOnSelf = true
                    } else {
                        avoidOnParent = true
                    }
                }
            }
            if avoidOnSelf { continue }

            var score = Double(min(peerCount, 25))
            var reasons: [String] = ["\(peerCount) vergelijkbare bestanden"]

            // Zelfde naamprefix (bv. "ES_" van Epidemic Sound) is heel sterk bewijs
            if let prefix = filePrefix, prefixCount >= 2 {
                score += 15 + Double(min(prefixCount, 25))
                reasons.append("\(prefixCount) met prefix \"\(prefix)\"")
            }

            // Keyword-affiniteit van het pad (dichterbij = sterker)
            var keywordHit = false
            for (index, component) in components.enumerated() {
                if Self.matchesAny(component, keywords: query.keywords) {
                    keywordHit = true
                    score += 4 + Double(index)
                }
            }
            if keywordHit { reasons.append("mapnaam past bij type") }

            // Pad hoort (deels) bij een ander asset type
            if avoidOnParent && !keywordHit { continue }
            if avoidOnParent { score -= 20 }

            // Subfolder-verfijning: bestaande submap die matcht op mood/genre/categorie
            if let sub = query.subfolder,
               let last = components.last,
               Self.normalize(last) == Self.normalize(sub) {
                score += 6
                reasons.append("submap komt overeen met \"\(sub)\"")
            }

            // Recent gebruikte mappen zijn waarschijnlijker het actieve doel
            if let recent = newestPeerDate,
               Date().timeIntervalSince(recent) < 30 * 86400 {
                score += 5
                reasons.append("recent gebruikt")
            }

            // Lichte voorkeur voor ondiepere mappen bij gelijk bewijs
            score -= Double(entry.depth) * 0.5

            guard score > 0 else { continue }

            candidates.append(PlacementCandidate(
                directoryURL: entry.url,
                relativePath: entry.relativePath,
                score: score,
                peerCount: peerCount,
                prefixCount: prefixCount,
                reason: reasons.joined(separator: ", ")
            ))
        }

        return candidates.sorted { $0.score > $1.score }
    }

    // MARK: - Matching helpers

    /// Token-gebaseerde keyword-match op een mapnaam.
    /// "Final Exports" → tokens ["final","exports"] → matcht keyword "exports" en (via prefix)
    /// "export". Korte keywords (< 6 tekens, zoals "audio", "sfx", "vo") vereisen een EXACTE
    /// token-match zodat "Audiobooks" niet op "audio" matcht.
    static func matchesAny(_ folderName: String, keywords: [String]) -> Bool {
        let normalized = normalize(folderName)
        let tokens = normalized.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." }).map(String.init)
        for keyword in keywords {
            for token in tokens {
                if token == keyword { return true }
                if keyword.count >= 6 && token.hasPrefix(keyword) { return true }
            }
            // Meerwoordige keywords ("sound effects") matchen op de hele genormaliseerde naam
            if keyword.contains(" ") && normalized.contains(keyword) { return true }
        }
        return false
    }

    /// Extraheer een naamprefix zoals "ES_" uit "ES_Higher (…).wav".
    /// Alleen korte prefixes vóór een underscore tellen (leverancier-conventies).
    static func namePrefix(of fileName: String) -> String? {
        guard let underscoreIndex = fileName.firstIndex(of: "_") else { return nil }
        let prefix = String(fileName[..<underscoreIndex])
        guard prefix.count >= 2, prefix.count <= 8 else { return nil }
        // Alleen letters/cijfers (geen spaties — dan is het geen leverancier-prefix)
        guard prefix.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return prefix + "_"
    }

    /// Normaliseer een mapnaam: strip nummer-prefix (03_) en lowercase.
    static func normalize(_ name: String) -> String {
        var normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = normalized.range(of: #"^\d+_"#, options: .regularExpression) {
            normalized = String(normalized[range.upperBound...])
        }
        return normalized
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }
}

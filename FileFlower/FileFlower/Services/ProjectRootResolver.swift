import Foundation

/// Eén gezaghebbende bron voor "wat is de hoofd-projectmap" — de map waaronder de asset-mappen
/// van DIT project horen (03_Audio, 02_Footage, …), gegeven een .prproj/.drp-pad of een projectmap.
///
/// **Kernregel:** de hoofd-projectmap is het **directe kind** van de geconfigureerde project-root
/// (de "projecten-container") op weg naar het project. Dit matcht exact hoe projecten in de config
/// staan (`…/01_Projects/PROJECT_A`, `…/01_Projects/PROJECT_B`, …) en is robuust ongeacht waar de
/// assets fysiek staan — ook bij geneste structuren als
/// `…/01_Projects/PROJECT_A/01_Projects/01_PremierePro/Video 10 Project/x.prproj` (→ root = `PROJECT_A`).
///
/// Voorheen klom de logica omhoog tot een map die "audio/footage-achtig" leek; bij een container met
/// een losse map als `PROJECT_A_FOOTAGE` koos die de container zelf → de scan leerde dan 500+ regels uit
/// ALLE projecten door elkaar. De kind-van-container-regel voorkomt dat per definitie.
final class ProjectRootResolver {
    static let shared = ProjectRootResolver()
    private init() {}

    /// Bestandsextensies die een echt project-BESTAND aanduiden (rest = project-MAP).
    private static let projectFileExtensions: Set<String> = ["prproj", "drp", "fcpbundle", "aep", "ppj", "fcp"]

    func mainFolder(forProjectPath projectPath: String, configuredRootHint: String?) -> URL {
        let fm = FileManager.default
        let prprojURL = URL(fileURLWithPath: projectPath)

        // Virtueel Resolve-pad (database-backed project zonder .drp op disk)
        if projectPath.hasPrefix("/resolve-project/") {
            if let hint = configuredRootHint, !hint.isEmpty, fm.fileExists(atPath: hint) {
                return URL(fileURLWithPath: hint)
            }
            return URL(fileURLWithPath: configuredRootHint ?? prprojURL.deletingLastPathComponent().path)
        }

        // Startpunt: bij een project-BESTAND de map ervan; bij een project-MAP de map zelf.
        // (Een project kan in de config gekeyd zijn op het .prproj-pad óf op de projectmap.)
        let isProjectFile = Self.projectFileExtensions.contains(prprojURL.pathExtension.lowercased())
        let startDir = isProjectFile ? prprojURL.deletingLastPathComponent() : prprojURL

        let roots = configuredRoots(hint: configuredRootHint)

        // PRIMAIR: kind-van-container-regel.
        if let root = deepestRoot(containing: startDir, roots: roots) {
            if let child = immediateChild(of: root, towards: startDir) {
                // Als het directe kind een NLE-/template-map is, dan IS de geconfigureerde root
                // zélf één project (bv. root `…/00_WEBSITE_VIDEO` met `01_Adobe/x.prproj` erin).
                if isNLEFolderName(child.lastPathComponent) {
                    return root
                }

                // GENESTE CONTAINERS: het directe kind kan zelf óók een container zijn
                // (bv. root/KlantA/ProjectB/01_Adobe/x.prproj — KlantA bevat meerdere projecten).
                // Kies daarom de EERSTE map op het pad root→project die structureel een
                // projecthoofdmap is (asset-submappen heeft). Voor de normale situatie is dat
                // gewoon het directe kind zelf.
                var walker: URL? = child
                while let current = walker {
                    if looksLikeProjectRoot(directorySubfolderNames(at: current, fm: fm)) {
                        return current
                    }
                    if current.standardizedFileURL.path == startDir.standardizedFileURL.path { break }
                    walker = immediateChild(of: current, towards: startDir)
                }

                // VALIDATIE tegen vergiftigde roots: als een geconfigureerde root per ongeluk
                // BINNEN een project wijst (bv. auto-added `…/<project>/01_Projects/01_PremierePro`),
                // dan is het "kind" hier de kale .prproj-map zonder asset-structuur. Herken dat:
                // het projectbestand ligt direct in het kind, het kind heeft zelf geen asset-mappen,
                // maar een voorouder er vlak boven wél → dan is DIE de echte projecthoofdmap.
                // De klim stopt bij beschermde grenzen (home bevat altijd "Music"!).
                if isProjectFile,
                   startDir.standardizedFileURL.path == child.standardizedFileURL.path,
                   !looksLikeProjectRoot(directorySubfolderNames(at: child, fm: fm)) {
                    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
                    var ancestor = child.deletingLastPathComponent()
                    for _ in 0..<4 {
                        let ancestorPath = ancestor.standardizedFileURL.path
                        if ancestorPath == "/" || ancestorPath == home ||
                           ancestorPath == "/Users" || ancestorPath == "/Volumes" {
                            break
                        }
                        if looksLikeProjectRoot(directorySubfolderNames(at: ancestor, fm: fm)) {
                            #if DEBUG
                            print("ProjectRootResolver: geconfigureerde root wijst binnen een project; gecorrigeerd naar \(ancestor.path)")
                            #endif
                            return ancestor
                        }
                        ancestor = ancestor.deletingLastPathComponent()
                    }
                }

                return child
            }
            // startDir == root → het project ligt direct in de root → root is de projectmap.
            return root
        }

        // FALLBACK (project buiten álle geconfigureerde roots): klim en herken de root aan
        // audio/footage-submappen; anders de eerste niet-NLE-map vanaf het startpunt.
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        var current = startDir
        while current.path != "/" {
            if looksLikeProjectRoot(directorySubfolderNames(at: current, fm: fm)) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path == home { break }
            current = parent
        }
        var fallback = startDir
        while fallback.path != "/" {
            if !isNLEFolderName(fallback.lastPathComponent) {
                return fallback
            }
            let parent = fallback.deletingLastPathComponent()
            if parent.path == fallback.path { break }
            fallback = parent
        }
        return startDir
    }

    // MARK: - Helpers

    private func configuredRoots(hint: String?) -> [String] {
        var roots = AppState.shared.config.projectRoots
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty && $0 != "/" }
        if roots.isEmpty, let hint = hint, !hint.isEmpty {
            roots = [URL(fileURLWithPath: hint).standardizedFileURL.path]
        }
        return roots
    }

    /// De diepste (meest specifieke) geconfigureerde root die `dir` bevat of eraan gelijk is.
    private func deepestRoot(containing dir: URL, roots: [String]) -> URL? {
        let p = dir.standardizedFileURL.path
        let matches = roots.filter { p == $0 || p.hasPrefix($0 + "/") }
        guard let best = matches.max(by: { $0.count < $1.count }) else { return nil }
        return URL(fileURLWithPath: best)
    }

    /// De map net ónder `root` op weg naar `dir` (het project zelf). nil als `dir == root`.
    private func immediateChild(of root: URL, towards dir: URL) -> URL? {
        let rootPath = root.standardizedFileURL.path
        var current = dir.standardizedFileURL
        while current.path != "/" {
            let parent = current.deletingLastPathComponent()
            if parent.standardizedFileURL.path == rootPath {
                return current
            }
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private func isNLEFolderName(_ name: String) -> Bool {
        if PathSafetyPolicy.isBlockedFolderName(name) { return true }
        let n = name.lowercased()
        return n.contains("adobe") || n.contains("premiere") || n.contains("davinci") ||
               n.contains("resolve") || n.contains("audio previews") || n.contains("auto-save") ||
               n.hasPrefix("01_")
    }

    /// Een echte project-root bevat een AUDIO- én/óf FOOTAGE-map. Gebruikt in de fallback
    /// (project buiten de geconfigureerde roots) én bij validatie tegen vergiftigde roots.
    /// Let op: lange samengestelde namen als "PROJECT_A_FOOTAGE" zijn losse projectmappen in een
    /// CONTAINER, geen asset-map — die mogen een container niet als projectroot laten kwalificeren.
    func looksLikeProjectRoot(_ folderNames: [String]) -> Bool {
        let lower = folderNames.map { $0.lowercased() }
        let hasAudio = lower.contains { n in
            (n.contains("audio") || n.contains("muziek") || n == "music" || n.hasPrefix("03_"))
                && !n.contains("preview") && !n.contains("adobe") && n.count <= 20
        }
        let hasFootage = lower.contains { n in
            (n == "footage" || n == "materiaal" || n == "beeldmateriaal" || n.hasPrefix("02_")
                || ((n.contains("footage") || n.contains("materiaal")) && n.count <= 12))
        }
        return hasAudio || hasFootage
    }

    /// Klim vanaf een projectbestand omhoog naar de eerste map die structureel als
    /// projecthoofdmap kwalificeert (heeft asset-submappen zoals 02_Footage/03_Audio).
    /// Retourneert nil als er binnen `maxLevels` geen herkenbare projectstructuur is —
    /// dan mag de aanroeper NIET gokken.
    func climbToStructuralProjectRoot(fromProjectFile projectPath: String, maxLevels: Int = 6) -> URL? {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        var current = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        for _ in 0..<maxLevels {
            if current.path == "/" || current.path == home { break }
            if looksLikeProjectRoot(directorySubfolderNames(at: current, fm: fm)) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Strengere variant van `looksLikeProjectRoot`, bedoeld voor beslissingen die de
    /// CONFIGURATIE van de gebruiker wijzigen. Twee verschillen:
    ///
    /// 1. Een kaal nummerprefix telt NIET. In een projecten-container heten de projectmappen
    ///    vaak "01_Klant", "02_Klant" — de losse `n.hasPrefix("02_")` in de soepele variant
    ///    maakte zo'n container ten onrechte tot projecthoofdmap.
    /// 2. Er is bewijs van AUDIO én FOOTAGE nodig, niet één van beide. Eén toevallige map
    ///    volstaat dan niet meer.
    ///
    /// Bewust conservatief: te weinig saneren laat hooguit een oude root staan, te veel
    /// saneren gooit een geldige projectmap uit de configuratie.
    func looksLikeProjectRootStrict(_ folderNames: [String]) -> Bool {
        let lower = folderNames.map { $0.lowercased() }
        let hasAudio = lower.contains { n in
            (n.contains("audio") || n.contains("muziek") || n.contains("music") || n.contains("geluid"))
                && !n.contains("preview") && !n.contains("adobe") && n.count <= 20
        }
        let hasFootage = lower.contains { n in
            (n.contains("footage") || n.contains("materiaal") || n.contains("beeldmateriaal")
                || n.contains("rushes")) && n.count <= 20
        }
        return hasAudio && hasFootage
    }

    /// Bevat deze map zélf projectmappen? Dan is het een gezonde projecten-container en mag
    /// hij nooit als "vergiftigde root" vervangen worden.
    func containsProjectFolders(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for child in children.prefix(40) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if isNLEFolderName(child.lastPathComponent) { continue }
            if looksLikeProjectRootStrict(directorySubfolderNames(at: child, fm: fm)) { return true }
        }
        return false
    }

    private func directorySubfolderNames(at url: URL, fm: FileManager) -> [String] {
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.compactMap { u in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return u.lastPathComponent
        }
    }
}

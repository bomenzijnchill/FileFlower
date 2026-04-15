import Foundation

/// Substitueert `[Parameter Name]`-placeholders in een FolderNode boom.
///
/// Post Haste-compatible format: `[Name]` wordt vervangen door parameter-waarde.
/// Als een parameter `folderBreak = true` heeft, wordt de waarde op `/` gesplitst
/// en expandeert één node naar een geneste keten.
///
/// Built-ins (lagere prioriteit dan user-defined parameters):
/// - `[Date]`    → yyyy-MM-dd
/// - `[Year]`    → yyyy
/// - `[Month]`   → MM
/// - `[Day]`     → dd
enum TemplatePlaceholderResolver {

    // MARK: - Public API

    /// Resolve de hele boom. Elke node met placeholders wordt vervangen door
    /// nul of meer concrete nodes (folderBreak kan één node in meerdere expanderen).
    static func resolve(tree: FolderNode,
                        parameters: [TemplateParameter],
                        values: [String: String]) -> FolderNode {
        let resolvedChildren = resolveChildren(tree.children, parameters: parameters, values: values)
        return FolderNode(
            id: tree.id,
            name: tree.name,
            relativePath: tree.relativePath,
            children: resolvedChildren
        )
    }

    /// Resolve één naam naar 1+ pad-segmenten. Bij folderBreak-tokens kan dit meer dan 1 deel teruggeven.
    static func resolveName(_ name: String,
                            parameters: [TemplateParameter],
                            values: [String: String]) -> [String] {
        guard name.contains("[") else { return [name] }

        // Zoek alle tokens en bepaal of er een folderBreak-token in zit
        let tokens = findTokens(in: name)
        let breakTokens = tokens.filter { token in
            parameters.first(where: { $0.title.caseInsensitiveEquals(token) })?.folderBreak == true
        }

        // Substitueer alle tokens
        var substituted = name
        for token in tokens {
            let replacement = replacementValue(for: token, parameters: parameters, values: values)
            substituted = substituted.replacingOccurrences(of: "[\(token)]", with: replacement)
        }

        // Als er folderBreak-tokens waren, mag de waarde '/' bevatten → split op '/'
        if !breakTokens.isEmpty, substituted.contains("/") {
            let parts = substituted
                .split(separator: "/", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? [substituted] : parts
        }

        return [substituted]
    }

    /// Haal een built-in waarde op voor een token (Date/Year/Month/Day). Nil als geen match.
    static func builtInValue(for key: String) -> String? {
        let lower = key.lowercased()
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: now)

        switch lower {
        case "date":
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: now)
        case "year":
            if let y = comps.year { return String(format: "%04d", y) }
            return nil
        case "month":
            if let m = comps.month { return String(format: "%02d", m) }
            return nil
        case "day":
            if let d = comps.day { return String(format: "%02d", d) }
            return nil
        default:
            return nil
        }
    }

    /// Geeft alle tokens terug die in een naam voorkomen (zonder de `[` / `]`).
    static func findTokens(in name: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inside = false
        for ch in name {
            if ch == "[" {
                inside = true
                current = ""
            } else if ch == "]" {
                if inside && !current.isEmpty {
                    tokens.append(current)
                }
                inside = false
                current = ""
            } else if inside {
                current.append(ch)
            }
        }
        return tokens
    }

    // MARK: - Private helpers

    private static func resolveChildren(_ children: [FolderNode],
                                        parameters: [TemplateParameter],
                                        values: [String: String]) -> [FolderNode] {
        var result: [FolderNode] = []
        for child in children {
            let resolvedNames = resolveName(child.name, parameters: parameters, values: values)
            let resolvedGrandchildren = resolveChildren(child.children, parameters: parameters, values: values)

            // Filter lege segmenten
            let cleanNames = resolvedNames.filter { !$0.isEmpty }
            if cleanNames.isEmpty { continue }

            // Bouw nested keten: eerste is top, laatste krijgt de children
            if cleanNames.count == 1 {
                result.append(FolderNode(
                    name: cleanNames[0],
                    relativePath: cleanNames[0],
                    children: resolvedGrandchildren
                ))
            } else {
                // Nesten: laatste is diepste, children komen daarin
                var current = FolderNode(
                    name: cleanNames.last!,
                    relativePath: cleanNames.joined(separator: "/"),
                    children: resolvedGrandchildren
                )
                for name in cleanNames.dropLast().reversed() {
                    current = FolderNode(
                        name: name,
                        relativePath: "",
                        children: [current]
                    )
                }
                result.append(current)
            }
        }
        return result
    }

    private static func replacementValue(for token: String,
                                         parameters: [TemplateParameter],
                                         values: [String: String]) -> String {
        // 1. Probeer exact parameter-title match
        if let param = parameters.first(where: { $0.title.caseInsensitiveEquals(token) }) {
            // Lookup op title (exact)
            if let v = values[param.title], !v.isEmpty {
                return v
            }
            return param.defaultValue
        }
        // 2. Fallback: waarden-dict op token-naam (voor het geval caller de keys via token set)
        if let v = values[token], !v.isEmpty {
            return v
        }
        // 3. Built-in
        if let builtIn = builtInValue(for: token) {
            return builtIn
        }
        // 4. Geen match → behoud oorspronkelijke token-tekst zodat user ziet wat ontbreekt
        return "[\(token)]"
    }
}

private extension String {
    func caseInsensitiveEquals(_ other: String) -> Bool {
        return self.compare(other, options: .caseInsensitive) == .orderedSame
    }
}

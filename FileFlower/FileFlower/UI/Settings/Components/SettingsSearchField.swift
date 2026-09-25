import SwiftUI

struct SettingsSearchResult: Identifiable {
    let id = UUID()
    let label: String
    let path: String
    let tab: SettingsTab
}

struct SettingsSearchField: View {
    @Binding var searchQuery: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.ink3)

            TextField("", text: $searchQuery, prompt: Text(String(localized: "settings.search.placeholder")).foregroundColor(.ink3))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.ink)
                .focused(isFocused)

            if searchQuery.isEmpty {
                Text("⌘F")
                    .font(.brandMono(size: 10))
                    .foregroundColor(.ink3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.line, lineWidth: 0.5)
                    )
                    .cornerRadius(4)
            } else {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.ink4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 30)
        .background(Color.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused.wrappedValue ? Color.brandBurntPeach : Color.line, lineWidth: isFocused.wrappedValue ? 1.5 : 1)
        )
        .cornerRadius(8)
        .shadow(color: isFocused.wrappedValue ? Color.brandBurntPeach.opacity(0.18) : .clear, radius: 3, y: 0)
    }
}

/// Static search index — port of SEARCH_INDEX from settings-app.jsx.
enum SettingsSearchIndex {
    static let all: [SettingsSearchResult] = base + bridgeEntries

    private static let base: [SettingsSearchResult] = [
        .init(label: "Toon project-picker bij download",       path: "Algemeen › Bij download",   tab: .general),
        .init(label: "Speel petal-animatie af",                path: "Algemeen › Bij download",   tab: .general),
        .init(label: "Open bridge-paneel automatisch",         path: "Algemeen › Bij download",   tab: .general),
        .init(label: "Start automatisch bij login",            path: "Algemeen › Bij opstarten",  tab: .general),
        .init(label: "Anonieme gebruiksstatistieken",          path: "Algemeen › Privacy",        tab: .general),
        .init(label: "Filter server-projecten op lokaal",      path: "Algemeen › Project gedrag", tab: .general),
        .init(label: "Project roots",                          path: "Bibliotheek",               tab: .library),
        .init(label: "Downloads-map",                          path: "Bibliotheek",               tab: .library),
        .init(label: "Mappen-template / preset",               path: "Mappenstructuur",           tab: .template),
        .init(label: "Mood vs Genre",                          path: "Classificatie › Muziek",    tab: .classification),
        .init(label: "Claude API-key",                         path: "Classificatie › Slim",      tab: .classification),
        .init(label: "SFX submappen",                          path: "Classificatie › SFX",       tab: .classification),
        .init(label: "Premiere op voorgrond",                  path: "Integraties › Premiere",    tab: .integrations),
        .init(label: "Resolve auto-import",                    path: "Integraties › Resolve",     tab: .integrations),
        .init(label: "Stock-websites lijst",                   path: "Integraties › Bronnen",     tab: .integrations),
        .init(label: "Licentie",                               path: "Account",                   tab: .account),
        .init(label: "Updates & beta-kanaal",                  path: "Account › Updates",         tab: .account),
        .init(label: "Reset alle voorkeuren",                  path: "Geavanceerd › Setup",       tab: .advanced),
    ]

    // Los aangehouden: `#if` mag niet binnen een array-literal staan.
    private static var bridgeEntries: [SettingsSearchResult] {
        #if canImport(BridgeKit)
        return [
            .init(label: "Verkenner openen",                   path: "Bridge › Verkenner",        tab: .bridge),
            .init(label: "Machinenaam",                        path: "Bridge › Machinenaam",      tab: .bridge),
            .init(label: "Bridge-downloadmap",                 path: "Bridge › Downloadmap",      tab: .bridge),
            .init(label: "Cache legen",                        path: "Bridge › Cache",            tab: .bridge),
            .init(label: "Gedeelde mappen en machines",        path: "Bridge",                    tab: .bridge),
        ]
        #else
        return []
        #endif
    }

    static func match(_ query: String, limit: Int = 7) -> [SettingsSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return all.filter {
            $0.label.lowercased().contains(trimmed) || $0.path.lowercased().contains(trimmed)
        }.prefix(limit).map { $0 }
    }
}

/// Floating overlay that shows search results inside the content area.
struct SearchOverlay: View {
    let results: [SettingsSearchResult]
    let onSelect: (SettingsSearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Button(action: { onSelect(result) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.ink3)
                        Text(result.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.ink)
                        Spacer()
                        Text(result.path)
                            .font(.brandMono(size: 11))
                            .foregroundColor(.ink3)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SearchResultButtonStyle())

                if index < results.count - 1 {
                    Divider().background(Color.line)
                }
            }
        }
        .background(Color.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.line2, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 6)
    }
}

private struct SearchResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.brandBurntPeach.opacity(0.12) : .clear)
    }
}

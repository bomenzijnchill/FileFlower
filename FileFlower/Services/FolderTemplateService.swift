import Foundation

/// Service voor het scannen van mappenstructuren en AI-analyse via backend proxy.
class FolderTemplateService {
    static let shared = FolderTemplateService()

    // Backend proxy URL — vervangt directe Anthropic API calls
    private static let proxyBaseURL = "https://fileflower-proxy.fileflower.workers.dev"
    private static let timeoutInterval: TimeInterval = 30.0
    private static let maxRetries = 1
    private static let maxScanDepth = 5

    private init() {}

    // MARK: - Folder Scanning

    /// Recursief mappen scannen en een FolderNode boom bouwen
    func scanFolderTree(at url: URL, maxDepth: Int = maxScanDepth) -> FolderNode {
        let rootName = url.lastPathComponent
        let children = scanChildren(at: url, relativeTo: url, currentDepth: 0, maxDepth: maxDepth)
        return FolderNode(name: rootName, relativePath: "", children: children)
    }

    private func scanChildren(at url: URL, relativeTo root: URL, currentDepth: Int, maxDepth: Int) -> [FolderNode] {
        guard currentDepth < maxDepth else { return [] }
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var nodes: [FolderNode] = []

        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let name = item.lastPathComponent
            let relativePath = item.path
                .replacingOccurrences(of: root.path + "/", with: "")

            let children = scanChildren(
                at: item,
                relativeTo: root,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth
            )

            nodes.append(FolderNode(name: name, relativePath: relativePath, children: children))
        }

        return nodes
    }

    // MARK: - Tree to String

    /// Converteer FolderNode boom naar leesbare tekst voor AI prompt
    func treeToString(_ node: FolderNode, indent: String = "") -> String {
        var result = "\(indent)\(node.name)/\n"
        for child in node.children {
            result += treeToString(child, indent: indent + "  ")
        }
        return result
    }

    // MARK: - AI Analyse

    /// Stuur mappenstructuur naar backend proxy voor AI-analyse
    func analyzeStructure(tree: FolderNode, deviceId: String) async throws -> FolderTypeMapping {
        let treeString = treeToString(tree)

        for attempt in 0...Self.maxRetries {
            if let result = try await performAnalysis(treeString: treeString, deviceId: deviceId) {
                return result
            }

            if attempt < Self.maxRetries {
                #if DEBUG
                print("FolderTemplateService: Poging \(attempt + 1) mislukt, retry...")
                #endif
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        throw FolderTemplateError.analysisFailedAllRetries
    }

    private func performAnalysis(treeString: String, deviceId: String) async throws -> FolderTypeMapping? {
        guard let url = URL(string: "\(Self.proxyBaseURL)/api/analyze-folder-structure") else {
            throw FolderTemplateError.invalidProxyURL
        }

        let requestBody: [String: Any] = [
            "folderTree": treeString,
            "action": "analyze_folder_structure"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.timeoutInterval = Self.timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            #if DEBUG
            print("FolderTemplateService: JSON encoding fout: \(error.localizedDescription)")
            #endif
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("FolderTemplateService: Ongeldig response type")
                #endif
                return nil
            }

            if httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    #if DEBUG
                    print("FolderTemplateService: HTTP \(httpResponse.statusCode) - \(errorBody.prefix(200))")
                    #endif
                }
                return nil
            }

            return parseProxyResponse(data: data)

        } catch {
            #if DEBUG
            print("FolderTemplateService: Netwerk fout: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Response Parsing

    private func parseProxyResponse(data: Data) -> FolderTypeMapping? {
        // Parse de proxy response (die de Claude API response doorgeeft)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            #if DEBUG
            print("FolderTemplateService: Kon proxy response niet parsen")
            #endif
            return nil
        }

        // Extraheer JSON uit de AI response tekst
        guard let mappingJSON = extractJSON(from: text) else {
            #if DEBUG
            print("FolderTemplateService: Geen JSON gevonden in response: \(text.prefix(200))")
            #endif
            return nil
        }

        guard let outputData = mappingJSON.data(using: .utf8),
              let output = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            #if DEBUG
            print("FolderTemplateService: Kon mapping JSON niet parsen")
            #endif
            return nil
        }

        // Parse de mapping
        let mapping = output["mapping"] as? [String: String] ?? [:]
        let description = output["description"] as? String

        return FolderTypeMapping(
            musicPath: mapping["Music"],
            sfxPath: mapping["SFX"],
            voPath: mapping["VO"],
            graphicsPath: mapping["Graphic"],
            motionGraphicsPath: mapping["MotionGraphic"],
            stockFootagePath: mapping["StockFootage"],
            description: description,
            analyzedAt: Date()
        )
    }

    /// Extraheer JSON object uit tekst (AI kan tekst rond het JSON object plaatsen)
    private func extractJSON(from text: String) -> String? {
        // Strip markdown code blocks (```json ... ```)
        var cleaned = text
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Probeer de opgeschoonde tekst als JSON
        if let data = cleaned.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return cleaned
        }

        // Zoek JSON object markers
        if let start = cleaned.range(of: "{"),
           let end = cleaned.range(of: "}", options: .backwards) {
            let jsonStr = String(cleaned[start.lowerBound...end.upperBound])
            if let data = jsonStr.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return jsonStr
            }
        }

        return nil
    }
}

// MARK: - Errors

enum FolderTemplateError: LocalizedError {
    case invalidProxyURL
    case analysisFailedAllRetries
    case noMappingReceived

    var errorDescription: String? {
        switch self {
        case .invalidProxyURL:
            return "Invalid proxy URL configuration"
        case .analysisFailedAllRetries:
            return "Folder analysis failed after all retries"
        case .noMappingReceived:
            return "No folder mapping received from AI"
        }
    }
}

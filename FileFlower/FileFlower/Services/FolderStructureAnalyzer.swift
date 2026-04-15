import Foundation

/// Analyseert de mappenstructuur van een project via de Claude API
/// om te bepalen welke mappen footage, audio, foto's etc. bevatten.
class FolderStructureAnalyzer {
    static let shared = FolderStructureAnalyzer()

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"
    private static let apiVersion = "2023-06-01"

    /// Gecachte analyses per project pad
    private var cache: [String: AnalysisResult] = [:]

    struct AnalysisResult {
        let rawFootagePath: String?
        let audioPath: String?
        let photoPath: String?
        let graphicsPath: String?
        let exportsPath: String?
        let adobePath: String?
        let analyzedAt: Date

        var isValid: Bool { Date().timeIntervalSince(analyzedAt) < 3600 } // 1 uur cache
    }

    /// Analyseer de mappenstructuur van een project
    func analyze(projectPath: String) async -> AnalysisResult? {
        // Check cache
        if let cached = cache[projectPath], cached.isValid {
            return cached
        }

        guard let apiKey = ClaudeClassificationStrategy.loadAPIKey(), !apiKey.isEmpty else {
            #if DEBUG
            print("FolderStructureAnalyzer: Geen API key")
            #endif
            return nil
        }

        // Scan mappenstructuur (max 3 niveaus diep)
        let tree = scanFolderTree(at: projectPath, maxDepth: 3)
        guard !tree.isEmpty else { return nil }

        let prompt = """
        Analyze this video/film production project folder structure. Identify which folders serve specific purposes.

        Folder structure:
        \(tree)

        For each category, return the RELATIVE path from the project root. Return null if not found.
        Categories:
        - rawFootage: where camera/raw footage files are stored (look for folders with video files, "footage", "raw", "materiaal", "video", "rushes")
        - audio: where audio/music/sound files go
        - photos: where photos/stills are stored
        - graphics: where graphics/designs/visual assets are stored
        - exports: where final exports/renders go
        - adobe: where Adobe project files (.prproj, .aep) are stored

        IMPORTANT: Return ONLY valid JSON, no explanation. Example:
        {"rawFootage":"PROMO MATERIAAL/VIDEO","audio":"03_Audio","photos":"PROMO MATERIAAL/AFBEELDINGEN","graphics":null,"exports":"99_EXPORT","adobe":"00_ADOBE"}
        """

        let result = await callAPI(prompt: prompt, apiKey: apiKey)
        if let result = result {
            cache[projectPath] = result
        }
        return result
    }

    /// Wis cache voor een project (bijv. na structuurwijziging)
    func invalidateCache(for projectPath: String) {
        cache.removeValue(forKey: projectPath)
    }

    // MARK: - Private

    private func scanFolderTree(at path: String, maxDepth: Int, currentDepth: Int = 0, prefix: String = "") -> String {
        guard currentDepth < maxDepth else { return "" }
        let url = URL(fileURLWithPath: path)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }

        var lines: [String] = []
        let dirs = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

        for dir in dirs {
            let name = dir.lastPathComponent
            // Skip systeem/temp mappen
            if name.hasPrefix(".") || name == "Auto-Save" || name == "Backup" { continue }
            let indent = String(repeating: "  ", count: currentDepth)
            lines.append("\(indent)\(name)/")
            let subtree = scanFolderTree(at: dir.path, maxDepth: maxDepth, currentDepth: currentDepth + 1, prefix: prefix + name + "/")
            if !subtree.isEmpty {
                lines.append(subtree)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func callAPI(prompt: String, apiKey: String) async -> AnalysisResult? {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15.0

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 200,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                #if DEBUG
                print("FolderStructureAnalyzer: API error \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                #endif
                return nil
            }

            // Parse Claude response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let textBlock = content.first(where: { $0["type"] as? String == "text" }),
                  let text = textBlock["text"] as? String else {
                return nil
            }

            // Extract JSON from response (handle markdown code blocks)
            let jsonString = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = jsonString.data(using: .utf8),
                  let mapping = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any?] else {
                #if DEBUG
                print("FolderStructureAnalyzer: Failed to parse JSON: \(text)")
                #endif
                return nil
            }

            let result = AnalysisResult(
                rawFootagePath: mapping["rawFootage"] as? String,
                audioPath: mapping["audio"] as? String,
                photoPath: mapping["photos"] as? String,
                graphicsPath: mapping["graphics"] as? String,
                exportsPath: mapping["exports"] as? String,
                adobePath: mapping["adobe"] as? String,
                analyzedAt: Date()
            )

            #if DEBUG
            print("FolderStructureAnalyzer: Analyse compleet — footage: \(result.rawFootagePath ?? "nil"), audio: \(result.audioPath ?? "nil")")
            #endif

            return result
        } catch {
            #if DEBUG
            print("FolderStructureAnalyzer: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

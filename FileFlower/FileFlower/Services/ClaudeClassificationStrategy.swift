import Foundation

/// Classificatie strategie via de Claude API (Anthropic Haiku model).
/// Vervangt MLX als primaire AI-classificatie met few-shot learning via correctie-history.
class ClaudeClassificationStrategy: ClassificationStrategy {

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"
    private static let keychainKey = "com.fileflower.claude-api-key"
    private static let apiVersion = "2023-06-01"
    private static let maxRetries = 1
    private static let timeoutInterval: TimeInterval = 15.0

    // MARK: - ClassificationStrategy Protocol

    func classify(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> AssetType {
        let result = await classifyWithDetails(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
        return result.assetType
    }

    // MARK: - Extended Classification

    /// Classificeer met volledige details (type, genre, mood, sfxCategory)
    func classifyWithDetails(
        url: URL,
        uti: String?,
        metadata: DownloadMetadata?,
        originUrl: String?
    ) async -> (assetType: AssetType, genre: String?, mood: String?, sfxCategory: String?) {
        guard let apiKey = Self.loadAPIKey(), !apiKey.isEmpty else {
            #if DEBUG
            print("ClaudeClassifier: Geen API key geconfigureerd")
            #endif
            return (.unknown, nil, nil, nil)
        }

        let filename = url.lastPathComponent
        let startTime = Date()

        // Probeer classificatie met retry
        for attempt in 0...Self.maxRetries {
            let result = await performClassification(
                filename: filename,
                metadata: metadata,
                originUrl: originUrl,
                apiKey: apiKey
            )

            if let result = result {
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                #if DEBUG
                print("ClaudeClassifier: \(result.assetType.displayName) in \(elapsed)ms (poging \(attempt + 1))")
                #endif
                return result
            }

            if attempt < Self.maxRetries {
                #if DEBUG
                print("ClaudeClassifier: Poging \(attempt + 1) mislukt, retry...")
                #endif
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s wachten
            }
        }

        #if DEBUG
        print("ClaudeClassifier: Alle pogingen mislukt, fallback naar unknown")
        #endif
        return (.unknown, nil, nil, nil)
    }

    // MARK: - API Communication

    private func performClassification(
        filename: String,
        metadata: DownloadMetadata?,
        originUrl: String?,
        apiKey: String
    ) async -> (assetType: AssetType, genre: String?, mood: String?, sfxCategory: String?)? {
        // Bouw de prompt
        let systemPrompt = buildSystemPrompt()
        let userMessage = buildUserMessage(filename: filename, metadata: metadata, originUrl: originUrl)

        // Bouw request body
        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 200,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = Self.timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            #if DEBUG
            print("ClaudeClassifier: JSON encoding fout: \(error.localizedDescription)")
            #endif
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("ClaudeClassifier: Ongeldig response type")
                #endif
                return nil
            }

            if httpResponse.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    #if DEBUG
                    print("ClaudeClassifier: HTTP \(httpResponse.statusCode) - \(errorBody.prefix(200))")
                    #endif
                }
                return nil
            }

            return parseResponse(data: data)

        } catch {
            #if DEBUG
            print("ClaudeClassifier: Netwerk fout: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data) -> (assetType: AssetType, genre: String?, mood: String?, sfxCategory: String?)? {
        // Parse de Claude API response structuur
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            #if DEBUG
            print("ClaudeClassifier: Kon response niet parsen")
            #endif
            return nil
        }

        // Zoek JSON in de response text (Claude kan soms extra tekst toevoegen)
        guard let classificationJSON = extractJSON(from: text) else {
            #if DEBUG
            print("ClaudeClassifier: Geen JSON gevonden in response: \(text.prefix(200))")
            #endif
            return nil
        }

        // Parse de classificatie output
        guard let outputData = classificationJSON.data(using: .utf8),
              let output = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            #if DEBUG
            print("ClaudeClassifier: Kon classificatie JSON niet parsen")
            #endif
            return nil
        }

        let assetTypeStr = output["assetType"] as? String ?? "Unknown"
        let genre = output["genre"] as? String
        let mood = output["mood"] as? String
        let sfxCategory = output["sfxCategory"] as? String

        let assetType = parseAssetType(assetTypeStr)

        return (assetType, genre, mood, sfxCategory)
    }

    /// Extraheer JSON object uit tekst (Claude kan tekst rond het JSON object plaatsen)
    private func extractJSON(from text: String) -> String? {
        // Probeer de hele tekst als JSON
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return text
        }

        // Zoek naar eerste { en laatste }
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            return nil
        }

        let jsonSubstring = String(text[startIndex...endIndex])
        if let data = jsonSubstring.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return jsonSubstring
        }

        return nil
    }

    private func parseAssetType(_ typeString: String) -> AssetType {
        let lowercased = typeString.lowercased()
        switch lowercased {
        case "music": return .music
        case "sfx": return .sfx
        case "vo", "voice", "voiceover": return .vo
        case "motiongraphic", "motion graphic", "motion-graphic": return .motionGraphic
        case "graphic": return .graphic
        case "stockfootage", "stock footage", "stock-footage": return .stockFootage
        default: return .unknown
        }
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        return """
        You are a media asset classifier for video production workflows. Classify the given file into exactly one type based on filename, metadata, and context.

        Valid asset types:
        - Music: Background music, songs, instrumentals, beats, scores
        - SFX: Sound effects, foley, ambience, nature sounds, impacts, whooshes, UI sounds, transitions
        - VO: Voice-over, narration, dialogue, speech recordings
        - MotionGraphic: Motion graphic templates (.mogrt), animated titles, lower thirds
        - Graphic: Static images, photos, illustrations for video production
        - StockFootage: Stock video clips, B-roll footage

        Important rules:
        - Files from Epidemic Sound, Artlist, etc. with descriptive names like "Organic, Wind, Cool" are typically SFX, NOT music
        - Nature sounds (wind, rain, thunder, water, fire, birds) are always SFX
        - Short audio files (<10 seconds) are usually SFX
        - Files with BPM, key signature, or artist names are usually Music
        - "ES_" prefix = Epidemic Sound. Check the descriptive words carefully to distinguish Music vs SFX

        For Music: also determine genre and mood
        For SFX: also determine a category (e.g. "Wind", "Impacts", "Whooshes", "Ambience", "Foley", "UI", "Transitions")

        Respond with ONLY a JSON object, no other text:
        {"assetType": "SFX", "genre": null, "mood": null, "sfxCategory": "Wind"}
        """
    }

    private func buildUserMessage(filename: String, metadata: DownloadMetadata?, originUrl: String?) -> String {
        var parts: [String] = []

        parts.append("Filename: \(filename)")
        parts.append("Extension: \(URL(fileURLWithPath: filename).pathExtension)")

        // Metadata
        if let meta = metadata {
            if let duration = meta.duration { parts.append("Duration: \(duration) seconds") }
            if let bpm = meta.bpm { parts.append("BPM: \(bpm)") }
            if let key = meta.key { parts.append("Key: \(key)") }
            if let artist = meta.artist, !artist.isEmpty { parts.append("Artist: \(artist)") }
            if let title = meta.title, !title.isEmpty { parts.append("Title: \(title)") }
            if let genre = meta.genre, !genre.isEmpty { parts.append("Genre tag: \(genre)") }
            if !meta.tags.isEmpty { parts.append("Tags: \(meta.tags.joined(separator: ", "))") }
            if let sampleRate = meta.sampleRate { parts.append("Sample rate: \(sampleRate) Hz") }
            if let width = meta.width, let height = meta.height {
                parts.append("Resolution: \(width)x\(height)")
            }
        }

        // Origin URL (source platform hint)
        if let origin = originUrl {
            parts.append("Origin URL: \(origin)")
        }

        // Few-shot correctie-voorbeelden
        let corrections = CorrectionHistoryManager.shared.relevantExamples(
            for: filename,
            source: nil, // Source is hier niet beschikbaar, maar de manager matcht ook op extensie
            limit: 8
        )

        if !corrections.isEmpty {
            parts.append("")
            parts.append("User correction history (learn from these):")
            for correction in corrections {
                var example = "- \"\(correction.filename)\" was classified as \(correction.originalPrediction.rawValue) but user corrected to \(correction.correctedType.rawValue)"
                if let source = correction.detectedSource {
                    example += " (source: \(source.rawValue))"
                }
                parts.append(example)
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - API Key Management

    static func loadAPIKey() -> String? {
        return KeychainHelper.load(key: keychainKey)
    }

    static func saveAPIKey(_ key: String) {
        if key.isEmpty {
            KeychainHelper.delete(key: keychainKey)
        } else {
            KeychainHelper.save(key: keychainKey, value: key)
        }
    }

    // MARK: - Connection Test

    /// Test de API connectie met een minimale request
    static func testConnection(apiKey: String) async -> Bool {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10.0

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "messages": [
                ["role": "user", "content": "Respond with: ok"]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return false }
            #if DEBUG
            print("ClaudeClassifier: Test connectie status: \(httpResponse.statusCode)")
            #endif
            return httpResponse.statusCode == 200
        } catch {
            #if DEBUG
            print("ClaudeClassifier: Test connectie fout: \(error.localizedDescription)")
            #endif
            return false
        }
    }
}

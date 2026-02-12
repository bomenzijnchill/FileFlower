import Foundation

/// Simpele HTTP client voor Supabase REST API
/// Stuurt analytics events als JSON naar de analytics_events tabel
class SupabaseClient {
    // TODO: Vervang deze waarden met je eigen Supabase project credentials
    // Ga naar https://supabase.com om een gratis project aan te maken
    // De anon key is veilig om in de app te bundelen (met RLS policies)
    private let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    private let supabaseAnonKey = "YOUR_ANON_KEY"
    private let tableName = "analytics_events"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    /// Stuur een batch events naar Supabase
    func sendEvents(_ events: [AnalyticsEvent], anonymousId: String, completion: @escaping (Bool) -> Void) {
        guard !supabaseURL.contains("YOUR_PROJECT") else {
            print("SupabaseClient: Supabase is nog niet geconfigureerd. Sla events lokaal op.")
            // Events worden lokaal opgeslagen maar niet verstuurd tot Supabase is geconfigureerd
            completion(true) // Return true zodat events niet steeds opnieuw geprobeerd worden
            return
        }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/\(tableName)") else {
            print("SupabaseClient: Ongeldige URL")
            completion(false)
            return
        }

        // Converteer events naar Supabase format
        let rows = events.map { event -> [String: Any] in
            var eventDataDict: [String: Any] = [:]
            for (key, value) in event.eventData {
                switch value {
                case .string(let s): eventDataDict[key] = s
                case .int(let i): eventDataDict[key] = i
                case .double(let d): eventDataDict[key] = d
                case .bool(let b): eventDataDict[key] = b
                }
            }

            let formatter = ISO8601DateFormatter()

            return [
                "anonymous_id": anonymousId,
                "event_type": event.eventType,
                "event_data": eventDataDict,
                "app_version": event.appVersion,
                "os_version": event.osVersion,
                "locale": event.locale,
                "created_at": formatter.string(from: event.timestamp)
            ]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: rows) else {
            print("SupabaseClient: Kan events niet serialiseren")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = jsonData

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("SupabaseClient: Netwerk fout: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("SupabaseClient: Geen HTTP response")
                completion(false)
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                completion(true)
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "geen body"
                print("SupabaseClient: HTTP \(httpResponse.statusCode) - \(body)")
                completion(false)
            }
        }

        task.resume()
    }
}

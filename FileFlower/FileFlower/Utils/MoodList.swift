import Foundation

class MoodList {
    static let shared = MoodList()
    
    let moods: [String]
    
    private init() {
        guard let url = Bundle.main.url(forResource: "mood_list", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            // Fallback list
            moods = [
                "Angry", "Busy & Frantic", "Changing Tempo", "Chasing", "Dark",
                "Dreamy", "Epic", "Happy", "Laid Back", "Mysterious",
                "Peaceful", "Relaxing", "Romantic", "Sad", "Scary",
                "Sentimental", "Sexy", "Smooth", "Suspense", "Quirky", "Weird"
            ]
            return
        }
        moods = decoded
    }
}


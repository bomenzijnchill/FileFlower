import Foundation

class GenreList {
    static let shared = GenreList()
    
    let genres: [String]
    
    private init() {
        guard let url = Bundle.main.url(forResource: "genre_list", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            // Fallback list
            genres = [
                "EDM", "Hip Hop", "Pop", "Rock", "Cinematic", "Ambient",
                "DnB", "House", "Orchestral", "Jazz", "Blues", "Country",
                "Folk", "Reggae", "Latin", "World", "Electronic", "Techno",
                "Trance", "Dubstep"
            ]
            return
        }
        genres = decoded
    }
}


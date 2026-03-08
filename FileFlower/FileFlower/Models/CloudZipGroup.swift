import Foundation

/// Representeert een groep gerelateerde Google Drive ZIP-delen
struct CloudZipGroup: Identifiable {
    let id: UUID
    let baseName: String           // bijv. "ROAD TO EWC-20260205T124843Z-3"
    let expectedPartCount: Int     // bijv. 3 (uit "-3-" in bestandsnaam)
    var receivedParts: [CloudZipPart]
    var firstDetectedAt: Date
    var lastPartReceivedAt: Date
    var originURL: String?

    var isComplete: Bool {
        receivedParts.count >= expectedPartCount
    }

    /// Google Drive ZIP naampatroon: {MapNaam}-{timestamp}-{AantalDelen}-{Deelnummer}.zip
    /// Voorbeeld: "ROAD TO EWC-20260205T124843Z-3-001.zip" (deel 1 van 3)
    static func parse(filename: String) -> ParsedZipPart? {
        // Patroon: eindigt op -{N}-{NNN}.zip waar N = totaal delen, NNN = deelnummer
        let pattern = #"^(.+)-(\d{8}T\d{6}Z)-(\d+)-(\d{3})\.zip$"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: filename,
                  range: NSRange(filename.startIndex..., in: filename)
              ) else {
            return nil
        }

        guard match.numberOfRanges == 5,
              let folderRange = Range(match.range(at: 1), in: filename),
              let timestampRange = Range(match.range(at: 2), in: filename),
              let totalRange = Range(match.range(at: 3), in: filename),
              let partRange = Range(match.range(at: 4), in: filename) else {
            return nil
        }

        let folderName = String(filename[folderRange])
        let timestamp = String(filename[timestampRange])
        let totalParts = Int(String(filename[totalRange])) ?? 0
        let partNumber = Int(String(filename[partRange])) ?? 0

        let baseName = "\(folderName)-\(timestamp)-\(totalParts)"
        return ParsedZipPart(
            baseName: baseName,
            folderName: folderName,
            totalParts: totalParts,
            partNumber: partNumber
        )
    }
}

struct CloudZipPart: Identifiable {
    let id: UUID
    let url: URL
    let partNumber: Int
}

struct ParsedZipPart {
    let baseName: String
    let folderName: String
    let totalParts: Int
    let partNumber: Int
}

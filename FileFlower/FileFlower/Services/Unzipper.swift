import Foundation
import Compression

class Unzipper {
    static func unzip(_ sourceURL: URL, to destinationURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        
        // Create destination folder with zip name (without extension)
        let zipName = sourceURL.deletingPathExtension().lastPathComponent
        let extractFolder = destinationURL.appendingPathComponent(zipName, isDirectory: true)
        
        try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
        
        // Use Archive framework (macOS 10.15+)
        if #available(macOS 10.15, *) {
            return try unzipWithArchive(sourceURL: sourceURL, destination: extractFolder)
        } else {
            // Fallback to command line unzip
            return try unzipWithCommandLine(sourceURL: sourceURL, destination: extractFolder)
        }
    }
    
    @available(macOS 10.15, *)
    private static func unzipWithArchive(sourceURL: URL, destination: URL) throws -> [URL] {
        // Archive framework doesn't have direct zip support, use command line
        return try unzipWithCommandLine(sourceURL: sourceURL, destination: destination)
    }
    
    private static func unzipWithCommandLine(sourceURL: URL, destination: URL) throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", sourceURL.path, "-d", destination.path]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw UnzipperError.unzipFailed(errorString)
        }
        
        // List extracted files
        let fileManager = FileManager.default
        var extractedFiles: [URL] = []
        
        if let enumerator = fileManager.enumerator(
            at: destination,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    extractedFiles.append(fileURL)
                }
            }
        }
        
        return extractedFiles
    }
}

enum UnzipperError: Error {
    case unzipFailed(String)
}

extension Unzipper {
    /// Controleert of een ZIP bestand alleen muziekbestanden bevat (WAV, MP3, AIFF, etc.)
    static func containsOnlyMusic(_ sourceURL: URL) -> Bool {
        // Gebruik zipinfo voor een schonere output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", sourceURL.path]  // -1 = alleen bestandsnamen, één per regel
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                #if DEBUG
                print("Unzipper: zipinfo failed with status \(process.terminationStatus)")
                #endif
                // Fallback: check filename for music keywords
                return checkFilenameForMusic(sourceURL)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                #if DEBUG
                print("Unzipper: Could not decode zipinfo output")
                #endif
                return checkFilenameForMusic(sourceURL)
            }
            
            // Audio file extensions that indicate music
            let audioExtensions = ["wav", "mp3", "aiff", "aif", "m4a", "aac", "flac", "ogg"]
            
            // Parse de output - één bestandsnaam per regel
            let lines = output.components(separatedBy: .newlines)
            var hasFiles = false
            var allMusic = true
            var fileCount = 0
            
            for line in lines {
                let filename = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip empty lines
                if filename.isEmpty {
                    continue
                }
                
                // Skip directories (end with /)
                if filename.hasSuffix("/") {
                    continue
                }
                
                // Get the file extension from the last path component
                let lastComponent = (filename as NSString).lastPathComponent
                let ext = (lastComponent as NSString).pathExtension.lowercased()
                
                // Skip if no extension (likely a directory entry)
                if ext.isEmpty {
                    continue
                }
                
                // Found a file
                hasFiles = true
                fileCount += 1
                
                #if DEBUG
                print("Unzipper: Found file: \(lastComponent) (ext: \(ext))")
                #endif
                
                // Check if it's an audio file
                if !audioExtensions.contains(ext) {
                    #if DEBUG
                    print("Unzipper: Non-audio file detected: \(lastComponent)")
                    #endif
                    allMusic = false
                    break
                }
            }
            
            #if DEBUG
            print("Unzipper: ZIP contains \(fileCount) files, all music: \(allMusic)")
            #endif
            return hasFiles && allMusic
        } catch {
            #if DEBUG
            print("Unzipper: Error checking ZIP contents: \(error)")
            #endif
            return checkFilenameForMusic(sourceURL)
        }
    }
    
    /// Fallback: check ZIP filename for music keywords
    private static func checkFilenameForMusic(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        
        // Music-related keywords
        let musicKeywords = ["stems", "stem", "music", "track", "song", "beat", "melody", 
                            "bass", "drums", "instruments", "vocals", "vocal"]
        
        let hasMusic = musicKeywords.contains { filename.contains($0) }
        #if DEBUG
        print("Unzipper: Fallback check - filename '\(url.lastPathComponent)' contains music keywords: \(hasMusic)")
        #endif
        return hasMusic
    }
    
    /// Geeft de map terug waarin de ZIP wordt uitgepakt (zonder uit te pakken)
    static func getExtractFolderName(for sourceURL: URL, in destinationURL: URL) -> URL {
        let zipName = sourceURL.deletingPathExtension().lastPathComponent
        return destinationURL.appendingPathComponent(zipName, isDirectory: true)
    }
}


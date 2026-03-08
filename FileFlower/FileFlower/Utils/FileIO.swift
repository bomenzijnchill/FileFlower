import Foundation

extension FileManager {
    func fileSize(at url: URL) -> Int64? {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        
        if isDirectory.boolValue {
            // Calculate total size of directory
            return directorySize(at: url)
        } else {
            // Regular file
            guard let attrs = try? attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64 else {
                return nil
            }
            return size
        }
    }
    
    func directorySize(at url: URL) -> Int64? {
        var totalSize: Int64 = 0
        
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        
        return totalSize
    }
    
    func isFileStable(at url: URL) -> Bool {
        // Check if file has quarantine attribute (still downloading)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-l", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return !output.contains("com.apple.quarantine")
    }
}


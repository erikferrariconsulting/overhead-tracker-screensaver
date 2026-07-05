import Foundation
import AppKit

public struct ScreensaverInstaller {
    public enum InstallError: LocalizedError {
        case bundleNotFound
        case copyFailed(Error)
        case openFailed
        
        public var errorDescription: String? {
            switch self {
            case .bundleNotFound:
                return "Could not locate the embedded screensaver bundle in the app resources."
            case .copyFailed(let error):
                return "Failed to copy screensaver to Downloads: \(error.localizedDescription)"
            case .openFailed:
                return "Failed to open screensaver installer in System Settings."
            }
        }
    }

    public static func install() throws {
        // 1. Locate the embedded .saver bundle
        guard let sourceURL = Bundle.main.url(forResource: "OverheadTrackerScreensaver", withExtension: "saver") else {
            throw InstallError.bundleNotFound
        }
        
        // 2. Target the user's Downloads directory
        let fileManager = FileManager.default
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw InstallError.copyFailed(NSError(domain: "ScreensaverInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloads directory not available."]))
        }
        
        let destinationURL = downloadsURL.appendingPathComponent("OverheadTrackerScreensaver.saver")
        
        // 3. Remove existing file in Downloads if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        
        // 4. Copy the bundle to Downloads
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw InstallError.copyFailed(error)
        }
        
        // 4.5 Strip all extended attributes recursively to bypass Gatekeeper warning for local sandbox write
        stripAllAttributesRecursively(at: destinationURL)
        
        // 5. Open it to launch macOS system installation
        if !NSWorkspace.shared.open(destinationURL) {
            throw InstallError.openFailed
        }
    }

    private static func stripAllAttributesRecursively(at url: URL) {
        stripAllAttributes(at: url.path)
        
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    stripAllAttributes(at: fileURL.path)
                }
            }
        }
    }

    private static func stripAllAttributes(at path: String) {
        let listSize = listxattr(path, nil, 0, 0)
        guard listSize > 0 else { return }
        
        var buffer = [CChar](repeating: 0, count: listSize)
        let bytesRead = listxattr(path, &buffer, listSize, 0)
        guard bytesRead > 0 else { return }
        
        let data = Data(bytes: buffer, count: bytesRead)
        let attributeNames = data.split(separator: 0).compactMap { subdata -> String? in
            String(data: subdata, encoding: .utf8)
        }
        
        for attrName in attributeNames {
            if !attrName.isEmpty {
                removexattr(path, attrName, 0)
            }
        }
    }
}

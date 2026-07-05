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
        
        // 4.5 Strip quarantine extended attributes to bypass Gatekeeper warning for local build
        let task = Process()
        task.launchPath = "/usr/bin/xattr"
        task.arguments = ["-cr", destinationURL.path]
        try? task.run()
        task.waitUntilExit()
        
        // 5. Open it to launch macOS system installation
        if !NSWorkspace.shared.open(destinationURL) {
            throw InstallError.openFailed
        }
    }
}

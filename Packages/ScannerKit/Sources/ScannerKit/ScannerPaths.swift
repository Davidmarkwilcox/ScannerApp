// ScannerPaths.swift
// File: ScannerPaths.swift
// Description:
// Provides app-private filesystem locations for ScannerKit.
// - Resolves the Application Support root folder used by ScannerKit.
// - Ensures required directories exist (e.g., Application Support/Scanner/...).
// - Used by ScannerDocumentPaths and persistence logic to avoid Files.app clutter.
//
// Debug Logging:
// - Uses ScannerDebug (if present) or falls back to print when DEBUG is true.
// - Default debug mode is Off; toggle via ScannerPaths.setDebugEnabled(true).
//
// Section 1. Imports
import Foundation

// Section 2. ScannerPaths
public enum ScannerPaths {

    // Section 2.1 Debug toggle (default Off)
    private static var isDebugEnabled: Bool = false

    /// Enable/disable debug logs for path creation and resolution.
    public static func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }

    // Section 2.2 Root folder name
    private static let rootFolderName = "Scanner"

    // Section 2.3 Base URL
    /// Application Support/Scanner/
    public static func appSupportRootURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let root = appSupport.appendingPathComponent(rootFolderName, isDirectory: true)
        return try ensureDirectoryURL(root, fileManager: fileManager)
    }

    // Section 2.4 Directory ensuring
    /// Ensures the provided directory URL exists, creating it if needed.
    /// - Returns: The same URL, for call-site convenience.
    @discardableResult
    public static func ensureDirectoryURL(_ url: URL, fileManager: FileManager = .default) throws -> URL {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)

        if exists {
            if !isDir.boolValue {
                throw NSError(
                    domain: "ScannerPaths",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Expected directory but found file at: \(url.path)"]
                )
            }
            debugLog("Directory exists: \(url.path)")
            return url
        }

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        debugLog("Created directory: \(url.path)")
        return url
    }

    // Section 2.5 Subpaths
    /// Convenience for Application Support/Scanner/<subpath>
    public static func urlInRoot(_ subpath: String, isDirectory: Bool = true, fileManager: FileManager = .default) throws -> URL {
        let root = try appSupportRootURL(fileManager: fileManager)
        let url = root.appendingPathComponent(subpath, isDirectory: isDirectory)
        if isDirectory {
            return try ensureDirectoryURL(url, fileManager: fileManager)
        } else {
            return url
        }
    }

    // Section 2.6 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }

        // If your project defines ScannerDebug, prefer it.
        // Otherwise fall back to print.
        #if canImport(ScannerKitUI)
        // no-op: avoid accidental dependency
        #endif

        // Attempt to call ScannerDebug if available in the app target.
        // We can't import it here without coupling, so use print.
        print("ScannerPaths: \(message)")
    }
}

// ScannerPaths.swift

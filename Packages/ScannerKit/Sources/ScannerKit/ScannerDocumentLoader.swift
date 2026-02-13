// ScannerDocumentLoader.swift
// File: ScannerDocumentLoader.swift
// Description:
// Loads persisted ScannerKit documents from the app-private filesystem.
// - v1: loads page JPEGs from Application Support/Scanner/Documents/<UUID>/pages/###.jpg
// - Returns pages as [ScannedPage] for UI consumption.
// - Intended to back Viewer navigation from the Library.
//
// Interactions:
// - Uses ScannerDocumentPaths to resolve the document directory layout.
// - Used by ScannerApp's LibraryView when a user selects a document.
//
// Debug Logging:
// - Default debug mode is Off.
// - Enable via ScannerDocumentLoader.setDebugEnabled(true).
//
// Section 1. Imports
import Foundation
import UIKit

// Section 2. ScannerDocumentLoader
public enum ScannerDocumentLoader {

    // Section 2.1 Debug toggle (default Off)
    private static var isDebugEnabled: Bool = false

    public static func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }

    // Section 2.2 Errors
    public enum LoaderError: Error, LocalizedError {
        case pagesDirectoryMissing(path: String)
        case noPagesFound(path: String)
        case failedToDecodeImage(path: String)

        public var errorDescription: String? {
            switch self {
            case .pagesDirectoryMissing(let path):
                return "Pages directory missing: \(path)"
            case .noPagesFound(let path):
                return "No page images found in: \(path)"
            case .failedToDecodeImage(let path):
                return "Failed to decode image at: \(path)"
            }
        }
    }

    // Section 2.3 Public API
    public static func loadPages(
        documentID: UUID,
        fileManager: FileManager = .default
    ) throws -> [ScannedPage] {

        let paths = ScannerDocumentPaths(documentID: documentID)
        let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: pagesDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw LoaderError.pagesDirectoryMissing(path: pagesDir.path)
        }

        // Collect .jpg files, sorted lexicographically (001.jpg, 002.jpg, ...)
        let urls = try fileManager.contentsOfDirectory(
            at: pagesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let pageFiles = urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !pageFiles.isEmpty else {
            throw LoaderError.noPagesFound(path: pagesDir.path)
        }

        var result: [ScannedPage] = []
        result.reserveCapacity(pageFiles.count)

        for (idx, url) in pageFiles.enumerated() {
            guard let image = UIImage(contentsOfFile: url.path) else {
                throw LoaderError.failedToDecodeImage(path: url.path)
            }

            // Use stable page index based on ordering.
            let page = ScannedPage(
                id: UUID(),
                pageIndex: idx,
                image: image,
                createdAt: Date()
            )
            result.append(page)
        }

        debugLog("Loaded \(result.count) pages for documentID=\(documentID.uuidString)")
        return result
    }

    // Section 2.4 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }
        print("ScannerDocumentLoader: \(message)")
    }
}

// End of file: ScannerDocumentLoader.swift

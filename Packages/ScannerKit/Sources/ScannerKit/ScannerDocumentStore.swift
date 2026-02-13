// ScannerDocumentStore.swift
// File: ScannerDocumentStore.swift
// Description:
// File-based document indexer/store for ScannerKit.
// - Lists documents by scanning Application Support/Scanner/Documents/<UUID>/metadata.json
// - v1 adds mutations:
//   - deleteDocument(documentID:) removes the entire document directory atomically.
//   - renameDocument(documentID:newTitle:) updates metadata.json (title + modifiedAt).
//
// Interactions:
// - Uses ScannerPaths to locate the Scanner root.
// - Uses ScannerDocumentPaths to resolve per-document directory URLs.
// - Uses ScannerDocumentMetadata for JSON schema.
// - ScannerApp's LibraryView calls listDocuments(), and will call delete/rename next.
//
// Debug Logging:
// - Default debug mode is Off.
// - Enable via ScannerDocumentStore.setDebugEnabled(true).
//
// Section 1. Imports
import Foundation

// Section 2. ScannerDocumentStore
public enum ScannerDocumentStore {

    // Section 2.1 Debug toggle (default Off)
    private static var isDebugEnabled: Bool = false

    public static func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }

    // Section 2.2 JSON coding helpers
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // Section 2.3 Public API - Listing
    /// Lists all documents that have a metadata.json file under Application Support/Scanner/Documents/<UUID>/
    /// - Returns: Documents sorted by modifiedAt descending.
    public static func listDocuments(fileManager: FileManager = .default) -> [ScannerDocumentMetadata] {
        do {
            let documentsRoot = try ScannerPaths.urlInRoot("Documents", isDirectory: true, fileManager: fileManager)

            let urls = try fileManager.contentsOfDirectory(
                at: documentsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let decoder = makeDecoder()
            var results: [ScannerDocumentMetadata] = []

            for url in urls {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }

                let metadataURL = url.appendingPathComponent("metadata.json", isDirectory: false)
                guard fileManager.fileExists(atPath: metadataURL.path) else { continue }

                do {
                    let data = try Data(contentsOf: metadataURL)
                    let metadata = try decoder.decode(ScannerDocumentMetadata.self, from: data)
                    results.append(metadata)
                } catch {
                    debugLog("Failed decoding metadata in \(url.lastPathComponent): \(error.localizedDescription)")
                    continue
                }
            }

            results.sort { $0.modifiedAt > $1.modifiedAt }
            debugLog("Listed \(results.count) documents")
            return results
        } catch {
            debugLog("List documents failed: \(error.localizedDescription)")
            return []
        }
    }

    // Section 2.4 Public API - Delete
    /// Deletes the entire document directory: Application Support/Scanner/Documents/<UUID>/
    public static func deleteDocument(
        documentID: UUID,
        fileManager: FileManager = .default
    ) throws {
        let paths = ScannerDocumentPaths(documentID: documentID)
        let root = try paths.documentRootURL(fileManager: fileManager)

        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
            debugLog("Deleted documentID=\(documentID.uuidString)")
        } else {
            debugLog("Delete skipped (missing) documentID=\(documentID.uuidString)")
        }
    }

    // Section 2.5 Public API - Rename
    /// Updates metadata.json title and modifiedAt. Returns the updated metadata.
    public static func renameDocument(
        documentID: UUID,
        newTitle: String,
        fileManager: FileManager = .default
    ) throws -> ScannerDocumentMetadata {

        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = trimmed.isEmpty ? "Untitled" : trimmed

        let paths = ScannerDocumentPaths(documentID: documentID)
        let metadataURL = try paths.metadataURL(fileManager: fileManager)

        let decoder = makeDecoder()
        let encoder = makeEncoder()

        let data = try Data(contentsOf: metadataURL)
        var metadata = try decoder.decode(ScannerDocumentMetadata.self, from: data)

        metadata.title = safeTitle
        metadata.modifiedAt = Date()

        let newData = try encoder.encode(metadata)
        try newData.write(to: metadataURL, options: [.atomic])

        debugLog("Renamed documentID=\(documentID.uuidString) -> \(safeTitle)")
        return metadata
    }

    // Section 2.6 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }
        print("ScannerDocumentStore: \(message)")
    }
}

// End of file: ScannerDocumentStore.swift

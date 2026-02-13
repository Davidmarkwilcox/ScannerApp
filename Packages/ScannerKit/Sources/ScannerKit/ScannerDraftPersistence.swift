// ScannerDraftPersistence.swift
// File: ScannerDraftPersistence.swift
// Description:
// File-based draft persistence for ScannerKit.
// - Creates a new document UUID and directory structure under Application Support/Scanner/Documents/<UUID>/
// - Writes metadata.json for Library listing.
// - Writes thumbnail.jpg (from first page; rendered thumbnail with fallback to compressed full image).
// - Writes each page as a JPEG into pages/###.jpg (no PDF generation yet).
//
// Interactions:
// - Uses ScannerDocumentPaths (ScannerDocumentPaths.swift) and ScannerPaths (ScannerPaths.swift).
// - Uses ScannerDocumentMetadata (ScannerDocumentMetadata.swift) for JSON metadata.
// - Called from ScannerApp UI (e.g., ReviewView) to persist a scan session as a resumable draft.
//
// Debug Logging:
// - Default debug mode is Off (internal debugLog).
// - App-layer logging is handled via ScannerDebug in ReviewView/LibraryView.
//
// Section 1. Imports
import Foundation
import UIKit

// Section 2. ScannerDraftPersistence
public enum ScannerDraftPersistence {

    // Section 2.1 Debug toggle (default Off)
    private static var isDebugEnabled: Bool = false

    public static func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }

    // Section 2.2 Draft save result
    public struct DraftSaveResult {
        public let documentID: UUID
        public let documentRootURL: URL
        public let pageCount: Int
    }

    // Section 2.3 Errors
    public enum DraftError: Error, LocalizedError {
        case emptyPages
        case failedToEncodeJPEG(pageIndex: Int)
        case thumbnailWriteFailed(path: String)

        public var errorDescription: String? {
            switch self {
            case .emptyPages:
                return "Cannot save draft: pages array is empty."
            case .failedToEncodeJPEG(let pageIndex):
                return "Failed to encode page \(pageIndex) as JPEG."
            case .thumbnailWriteFailed(let path):
                return "Failed to write thumbnail at: \(path)"
            }
        }
    }

    // Section 2.4 Metadata helpers
    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "'Scan-'yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func writeMetadata(_ metadata: ScannerDocumentMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(metadata)
        try data.write(to: url, options: [.atomic])
    }

    // Section 2.5 Thumbnail helpers
    private static func makeThumbnailJPEG(from image: UIImage, maxDimension: CGFloat = 256, jpegQuality: CGFloat = 0.85) -> Data? {
        return autoreleasepool {
            let size = image.size
            guard size.width > 0, size.height > 0 else { return nil }

            let scaleFactor = min(maxDimension / max(size.width, size.height), 1.0)
            let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)

            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            format.scale = 0

            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let rendered = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            return rendered.jpegData(compressionQuality: jpegQuality)
        }
    }

    // Section 2.6 Public API
    /// Saves a new draft document by writing metadata.json, thumbnail.jpg, and each page image to disk.
    @discardableResult
    public static func saveDraft(
        pages: [ScannedPage],
        jpegQuality: CGFloat = 0.9,
        fileManager: FileManager = .default
    ) throws -> DraftSaveResult {

        guard !pages.isEmpty else {
            throw DraftError.emptyPages
        }

        let documentID = UUID()
        let paths = ScannerDocumentPaths(documentID: documentID)

        // Ensure document directories exist.
        let docRoot = try paths.documentRootURL(fileManager: fileManager)
        let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)
        _ = try paths.outputDirectoryURL(fileManager: fileManager) // created but unused for drafts

        debugLog("Saving draft \(documentID.uuidString)")
        debugLog("Document root: \(docRoot.path)")
        debugLog("Pages dir: \(pagesDir.path)")

        // Write initial metadata.json for Library listing.
        let now = Date()
        let metadata = ScannerDocumentMetadata(
            documentID: documentID,
            title: defaultTitle(for: now),
            createdAt: now,
            modifiedAt: now,
            pageCount: pages.count,
            state: .draft
        )

        let metadataURL = try paths.metadataURL(fileManager: fileManager)
        try writeMetadata(metadata, to: metadataURL)
        debugLog("Wrote metadata -> \(metadataURL.lastPathComponent)")

        // Write thumbnail.jpg (from first page). Use rendered thumbnail with fallback to compressed full image.
        let thumbURL = try paths.thumbnailURL(fileManager: fileManager)

        if let first = pages.first {
            if let thumbData = makeThumbnailJPEG(from: first.image) {
                try thumbData.write(to: thumbURL, options: [.atomic])
                debugLog("Wrote thumbnail (rendered) -> \(thumbURL.lastPathComponent)")
            } else if let fallbackData = first.image.jpegData(compressionQuality: 0.65) {
                try fallbackData.write(to: thumbURL, options: [.atomic])
                debugLog("Wrote thumbnail (fallback) -> \(thumbURL.lastPathComponent)")
            } else {
                debugLog("Skipped thumbnail: failed to encode JPEG")
            }
        } else {
            debugLog("Skipped thumbnail: no pages")
        }

        // Verify thumbnail exists; if not, surface error so the app can report it.
        if !fileManager.fileExists(atPath: thumbURL.path) {
            throw DraftError.thumbnailWriteFailed(path: thumbURL.path)
        }

        // Write pages as 001.jpg, 002.jpg, ...
        for (idx, page) in pages.enumerated() {
            let pageNumber = idx + 1
            let url = try paths.pageImageURL(pageNumber: pageNumber, fileManager: fileManager)

            guard let data = page.image.jpegData(compressionQuality: jpegQuality) else {
                throw DraftError.failedToEncodeJPEG(pageIndex: idx)
            }

            try data.write(to: url, options: [.atomic])
            debugLog("Wrote page \(pageNumber) -> \(url.lastPathComponent)")
        }

        return DraftSaveResult(documentID: documentID, documentRootURL: docRoot, pageCount: pages.count)
    }

    // Section 2.7 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }
        print("ScannerDraftPersistence: \(message)")
    }
}

// End of file: ScannerDraftPersistence.swift

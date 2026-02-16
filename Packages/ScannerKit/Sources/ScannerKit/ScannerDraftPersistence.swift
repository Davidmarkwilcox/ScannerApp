// ScannerDraftPersistence.swift
// File: ScannerDraftPersistence.swift
// Description:
// File-based persistence for ScannerKit documents.
// - Creates/updates a document directory under Application Support/Scanner/Documents/<UUID>/
// - Writes metadata.json for Library listing.
// - Writes thumbnail.jpg (from first page; rendered thumbnail with fallback).
// - Writes each page as a JPEG into pages/###.jpg.
// - Provides finalizeDocument(...) to generate output/document.pdf and update metadata state.
//
// Interactions:
// - Uses ScannerDocumentPaths (ScannerDocumentPaths.swift) and ScannerPaths (ScannerPaths.swift).
// - Uses ScannerDocumentMetadata (ScannerDocumentMetadata.swift) for JSON metadata.
// - Called from ScannerApp UI (e.g., ReviewView) to persist a scan session as a resumable draft and to finalize PDFs.
//
// Debug Logging:
// - Default debug mode is Off (internal debugLog).
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

        // Metadata / PDF
        case metadataReadFailed(path: String)
        case pdfRenderFailed(path: String)
        case failedToLoadPersistedPage(filename: String)

        public var errorDescription: String? {
            switch self {
            case .emptyPages:
                return "Cannot save draft: pages array is empty."
            case .failedToEncodeJPEG(let pageIndex):
                return "Failed to encode page \(pageIndex) as JPEG."
            case .thumbnailWriteFailed(let path):
                return "Failed to write thumbnail at: \(path)"
            case .metadataReadFailed(let path):
                return "Failed to read metadata at: \(path)"
            case .pdfRenderFailed(let path):
                return "Failed to render PDF at: \(path)"
            case .failedToLoadPersistedPage(let filename):
                return "Failed to load persisted page image: \(filename)"
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

    private static func readMetadata(from url: URL) throws -> ScannerDocumentMetadata {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ScannerDocumentMetadata.self, from: data)
        } catch {
            throw DraftError.metadataReadFailed(path: url.path)
        }
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

    // Section 2.6 PDF helpers
    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = bounds.midX - (w / 2.0)
        let y = bounds.midY - (h / 2.0)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func renderPDF(
        to url: URL,
        pageImages: [UIImage],
        pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter in points
    ) throws {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        do {
            try renderer.writePDF(to: url) { context in
                for image in pageImages {
                    context.beginPage()
                    let rect = aspectFitRect(for: image.size, in: bounds)
                    image.draw(in: rect)
                }
            }
        } catch {
            throw DraftError.pdfRenderFailed(path: url.path)
        }
    }

    private static func atomicReplaceItem(at destinationURL: URL, withItemAt sourceURL: URL, fileManager: FileManager) throws {
        // Replace destination with source atomically when possible.
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func clearExistingJPGs(in pagesDir: URL, fileManager: FileManager) {
        if let existing = try? fileManager.contentsOfDirectory(at: pagesDir, includingPropertiesForKeys: nil) {
            for url in existing where url.pathExtension.lowercased() == "jpg" {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // Section 2.7 Public API (Create/Update Draft)
    /// Creates or updates a draft document by writing:
    /// - metadata.json
    /// - thumbnail.jpg
    /// - pages/###.jpg (overwritten to match provided order)
    ///
    /// IMPORTANT:
    /// - Pass a previously returned documentID to update the same document (prevents duplicates in the Library).
    @discardableResult
    public static func saveDraft(
        documentID: UUID? = nil,
        pages: [ScannedPage],
        jpegQuality: CGFloat = 0.9,
        fileManager: FileManager = .default
    ) throws -> DraftSaveResult {

        guard !pages.isEmpty else { throw DraftError.emptyPages }

        let id = documentID ?? UUID()
        let paths = ScannerDocumentPaths(documentID: id)

        // Ensure directories.
        let docRoot = try paths.documentRootURL(fileManager: fileManager)
        let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)
        _ = try paths.outputDirectoryURL(fileManager: fileManager)

        debugLog("saveDraft documentID=\(id.uuidString)")
        debugLog("Document root: \(docRoot.path)")
        debugLog("Pages dir: \(pagesDir.path)")

        // Determine metadata: preserve title/createdAt if updating an existing document.
        let now = Date()
        let metadataURL = try paths.metadataURL(fileManager: fileManager)
        var metadata: ScannerDocumentMetadata

        if fileManager.fileExists(atPath: metadataURL.path) {
            // Update existing metadata in-place.
            metadata = try readMetadata(from: metadataURL)
            metadata.modifiedAt = now
            metadata.pageCount = pages.count
            // Keep state unless it is missing; if it's draft, keep draft.
            // (Do NOT revert savedLocal/synced back to draft.)
        } else {
            metadata = ScannerDocumentMetadata(
                documentID: id,
                title: defaultTitle(for: now),
                createdAt: now,
                modifiedAt: now,
                pageCount: pages.count,
                state: .draft
            )
        }

        try writeMetadata(metadata, to: metadataURL)
        debugLog("Wrote metadata -> \(metadataURL.lastPathComponent)")

        // Thumbnail from first page.
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
        }

        if !fileManager.fileExists(atPath: thumbURL.path) {
            throw DraftError.thumbnailWriteFailed(path: thumbURL.path)
        }

        // Overwrite pages in canonical order.
        clearExistingJPGs(in: pagesDir, fileManager: fileManager)

        for (idx, page) in pages.enumerated() {
            let pageNumber = idx + 1
            let url = try paths.pageImageURL(pageNumber: pageNumber, fileManager: fileManager)

            guard let data = page.image.jpegData(compressionQuality: jpegQuality) else {
                throw DraftError.failedToEncodeJPEG(pageIndex: idx)
            }

            try data.write(to: url, options: [.atomic])
            debugLog("Wrote page \(pageNumber) -> \(url.lastPathComponent)")
        }

        return DraftSaveResult(documentID: id, documentRootURL: docRoot, pageCount: pages.count)
    }

    // Section 2.8 Public API (Finalize)
    /// Finalizes an existing draft by:
    /// - Writing pages/###.jpg in the provided order (overwriting any existing pages)
    /// - Generating output/document.pdf
    /// - Updating metadata.json (pageCount, modifiedAt, state = savedLocal)
    public static func finalizeDocument(
        documentID: UUID,
        pages: [ScannedPage],
        jpegQuality: CGFloat = 0.9,
        fileManager: FileManager = .default
    ) throws {

        guard !pages.isEmpty else { throw DraftError.emptyPages }

        let paths = ScannerDocumentPaths(documentID: documentID)

        // Ensure directories.
        let docRoot = try paths.documentRootURL(fileManager: fileManager)
        let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)
        let outputDir = try paths.outputDirectoryURL(fileManager: fileManager)

        debugLog("finalizeDocument documentID=\(documentID.uuidString)")
        debugLog("Document root: \(docRoot.path)")
        debugLog("Pages dir: \(pagesDir.path)")
        debugLog("Output dir: \(outputDir.path)")

        // (1) Overwrite pages in canonical order.
        clearExistingJPGs(in: pagesDir, fileManager: fileManager)

        var uiImages: [UIImage] = []
        uiImages.reserveCapacity(pages.count)

        for (idx, page) in pages.enumerated() {
            let pageNumber = idx + 1
            let url = try paths.pageImageURL(pageNumber: pageNumber, fileManager: fileManager)

            guard let data = page.image.jpegData(compressionQuality: jpegQuality) else {
                throw DraftError.failedToEncodeJPEG(pageIndex: idx)
            }

            try data.write(to: url, options: [.atomic])
            debugLog("Wrote page \(pageNumber) -> \(url.lastPathComponent)")
            uiImages.append(page.image)
        }

        // (2) Render PDF to temp, then atomically replace output/document.pdf
        let pdfURL = try paths.pdfURL(fileManager: fileManager)
        let tmpURL = outputDir.appendingPathComponent("document.tmp.pdf", isDirectory: false)

        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }

        try renderPDF(to: tmpURL, pageImages: uiImages)
        try atomicReplaceItem(at: pdfURL, withItemAt: tmpURL, fileManager: fileManager)
        debugLog("Wrote PDF -> \(pdfURL.lastPathComponent)")

        // (3) Update metadata.json
        let metadataURL = try paths.metadataURL(fileManager: fileManager)
        var metadata: ScannerDocumentMetadata
        if fileManager.fileExists(atPath: metadataURL.path) {
            metadata = try readMetadata(from: metadataURL)
        } else {
            // If finalize is called without a prior draft save, create baseline metadata.
            let now = Date()
            metadata = ScannerDocumentMetadata(
                documentID: documentID,
                title: defaultTitle(for: now),
                createdAt: now,
                modifiedAt: now,
                pageCount: pages.count,
                state: .draft
            )
        }

        metadata.pageCount = pages.count
        metadata.modifiedAt = Date()
        metadata.state = .savedLocal

        try writeMetadata(metadata, to: metadataURL)
        debugLog("Updated metadata state -> savedLocal")
    }

    // Section 2.9 Public API (Share)
    /// Returns the URL for output/document.pdf for the given document.
    /// - If the PDF already exists, returns it.
    /// - If missing (likely a draft), generates it from persisted page JPEGs, updates metadata to savedLocal,
    ///   and returns the new PDF URL.
    public static func pdfURLForSharing(
        documentID: UUID,
        fileManager: FileManager = .default
    ) throws -> URL {

        let paths = ScannerDocumentPaths(documentID: documentID)
        let pdfURL = try paths.pdfURL(fileManager: fileManager)

        // Fast-path: share existing finalized PDF.
        if fileManager.fileExists(atPath: pdfURL.path) {
            debugLog("pdfURLForSharing found existing PDF at: \(pdfURL.path)")
            return pdfURL
        }

        debugLog("pdfURLForSharing PDF missing; generating from persisted page JPEGs for documentID=\(documentID.uuidString)")

        // IMPORTANT:
        // Do NOT rely on metadata.pageCount here — on first save, metadata may exist before all files/state are fully settled.
        // Instead, derive pages from the on-disk /pages directory.
        let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)

        let jpgURLs: [URL] = try fileManager.contentsOfDirectory(
            at: pagesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "jpg" || ext == "jpeg"
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !jpgURLs.isEmpty else {
            debugLog("pdfURLForSharing found no page JPEGs in: \(pagesDir.path)")
            throw DraftError.emptyPages
        }

        var uiImages: [UIImage] = []
        uiImages.reserveCapacity(jpgURLs.count)

        for url in jpgURLs {
            guard let image = UIImage(contentsOfFile: url.path) else {
                throw DraftError.failedToLoadPersistedPage(filename: url.lastPathComponent)
            }
            uiImages.append(image)
        }

        // Render PDF to temp, then atomically replace output/document.pdf
        let outputDir = try paths.outputDirectoryURL(fileManager: fileManager)
        let tmpURL = outputDir.appendingPathComponent("document.tmp.pdf", isDirectory: false)

        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }

        try renderPDF(to: tmpURL, pageImages: uiImages)
        try atomicReplaceItem(at: pdfURL, withItemAt: tmpURL, fileManager: fileManager)
        debugLog("pdfURLForSharing wrote PDF -> \(pdfURL.lastPathComponent)")

        // Update metadata.json to reflect savedLocal.
        let metadataURL = try paths.metadataURL(fileManager: fileManager)
        var metadata: ScannerDocumentMetadata
        if fileManager.fileExists(atPath: metadataURL.path) {
            metadata = try readMetadata(from: metadataURL)
        } else {
            let now = Date()
            metadata = ScannerDocumentMetadata(
                documentID: documentID,
                title: defaultTitle(for: now),
                createdAt: now,
                modifiedAt: now,
                pageCount: uiImages.count,
                state: .draft
            )
        }

        metadata.pageCount = uiImages.count
        metadata.modifiedAt = Date()
        metadata.state = .savedLocal
        try writeMetadata(metadata, to: metadataURL)

        return pdfURL
    }


// Section 2.9.1 Public API (Share PDF with preferred filename)
/// Returns a share-ready PDF URL whose *filename* matches the provided preferred filename.
///
/// Notes:
/// - iOS share sheets typically use the `lastPathComponent` of the shared file URL as the default filename.
/// - The persisted PDF path is canonical (`output/document.pdf`). To share with a custom name, we create a
///   temporary copy using the desired filename and return that temporary URL.
///
/// - Parameters:
///   - documentID: The document identifier.
///   - preferredFilename: A human-friendly name (with or without ".pdf"). If empty/invalid, falls back to "document.pdf".
///   - fileManager: The file manager to use.
public static func pdfURLForSharing(
    documentID: UUID,
    preferredFilename: String?,
    fileManager: FileManager = .default
) throws -> URL {

    // Ensure the canonical PDF exists (generates it if missing).
    let canonicalPDFURL = try pdfURLForSharing(documentID: documentID, fileManager: fileManager)

    // Sanitize + ensure .pdf extension.
    let baseName = sanitizeShareFilename(preferredFilename) ?? "document"
    let finalName = baseName.lowercased().hasSuffix(".pdf") ? baseName : "\(baseName).pdf"

    // Build a deterministic temp location for the share copy.
    let shareDir = fileManager.temporaryDirectory.appendingPathComponent("ScannerShare", isDirectory: true)
    if !fileManager.fileExists(atPath: shareDir.path) {
        try fileManager.createDirectory(at: shareDir, withIntermediateDirectories: true)
    }

    let shareURL = shareDir.appendingPathComponent(finalName, isDirectory: false)

    // Replace any existing temp file (avoid share sheet showing stale content).
    if fileManager.fileExists(atPath: shareURL.path) {
        try? fileManager.removeItem(at: shareURL)
    }

    try fileManager.copyItem(at: canonicalPDFURL, to: shareURL)
    debugLog("pdfURLForSharing(preferredFilename) -> \(shareURL.lastPathComponent)")

    return shareURL
}

// Section 2.9.2 Public API (Metadata Title)
/// Returns the persisted metadata title for a document, if available.
public static func documentTitle(
    documentID: UUID,
    fileManager: FileManager = .default
) -> String? {

    do {
        let paths = ScannerDocumentPaths(documentID: documentID)
        let metadataURL = try paths.metadataURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(ScannerDocumentMetadata.self, from: data)
        return metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

// Section 2.9.3 Filename Sanitization
private static func sanitizeShareFilename(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

    // Remove a trailing .pdf (we will add it back consistently later).
    var name = raw
    if name.lowercased().hasSuffix(".pdf") {
        name = String(name.dropLast(4))
    }

    // Replace path separators and other commonly illegal filename characters.
    let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    name = name.components(separatedBy: illegal).joined(separator: "_")

    // Collapse whitespace runs.
    name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)

    // Avoid empty results.
    guard !name.isEmpty else { return nil }

    // Keep filenames reasonably short for share destinations.
    if name.count > 80 {
        name = String(name.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return name
}




// Section 2.10 Public API (Share Images)
/// Returns the on-disk page image URLs for the given document, sorted in page order (001.jpg, 002.jpg, ...).
/// - Notes:
///   - This does not generate anything. It simply returns persisted page JPEGs under /pages.
///   - If no page JPEGs exist, throws DraftError.emptyPages.
public static func pageImageURLsForSharing(
    documentID: UUID,
    fileManager: FileManager = .default
) throws -> [URL] {

    let paths = ScannerDocumentPaths(documentID: documentID)
    let pagesDir = try paths.pagesDirectoryURL(fileManager: fileManager)

    let jpgURLs: [URL] = try fileManager.contentsOfDirectory(
        at: pagesDir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    .filter { url in
        let ext = url.pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg"
    }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

    guard !jpgURLs.isEmpty else {
        debugLog("pageImageURLsForSharing found no page JPEGs in: \(pagesDir.path)")
        throw DraftError.emptyPages
    }

    debugLog("pageImageURLsForSharing returning \(jpgURLs.count) images from: \(pagesDir.path)")
    return jpgURLs
}


    // Section 2.10 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }
        print("ScannerDraftPersistence: \(message)")
    }
}

// End of file: ScannerDraftPersistence.swift

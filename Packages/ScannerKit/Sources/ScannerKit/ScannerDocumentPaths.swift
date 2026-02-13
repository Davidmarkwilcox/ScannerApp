// ScannerDocumentPaths.swift
// File: ScannerDocumentPaths.swift
// Description:
// Document-scoped filesystem path helpers for ScannerKit.
// - Builds the directory layout under Application Support/Scanner/Documents/<UUID>/
// - Ensures required directories exist (document root, pages/, output/)
// - Used by persistence logic to write/read metadata, thumbnails, page images, and the final PDF.
//
// Interactions:
// - Depends on ScannerPaths (ScannerPaths.swift) for locating Application Support/Scanner/
// - Will be used by draft saving and final PDF generation.
//
// Section 1. Imports
import Foundation

// Section 2. ScannerDocumentPaths
public struct ScannerDocumentPaths {

    // Section 2.1 Stored properties
    public let documentID: UUID

    // Section 2.2 Init
    public init(documentID: UUID) {
        self.documentID = documentID
    }

    // Section 2.3 Root folders
    /// Application Support/Scanner/Documents/
    public func documentsRootURL(fileManager: FileManager = .default) throws -> URL {
        // Ensure "Documents" exists under the Scanner root.
        return try ScannerPaths.urlInRoot("Documents", isDirectory: true, fileManager: fileManager)
    }

    /// Application Support/Scanner/Documents/<UUID>/
    public func documentRootURL(fileManager: FileManager = .default) throws -> URL {
        let docsRoot = try documentsRootURL(fileManager: fileManager)
        let root = docsRoot.appendingPathComponent(documentID.uuidString, isDirectory: true)
        return try ScannerPaths.ensureDirectoryURL(root, fileManager: fileManager)
    }

    // Section 2.4 File URLs (not auto-created)
    /// Application Support/Scanner/Documents/<UUID>/metadata.json
    public func metadataURL(fileManager: FileManager = .default) throws -> URL {
        return try documentRootURL(fileManager: fileManager)
            .appendingPathComponent("metadata.json", isDirectory: false)
    }

    /// Application Support/Scanner/Documents/<UUID>/thumbnail.jpg
    public func thumbnailURL(fileManager: FileManager = .default) throws -> URL {
        return try documentRootURL(fileManager: fileManager)
            .appendingPathComponent("thumbnail.jpg", isDirectory: false)
    }

    // Section 2.5 Directory URLs (ensured)
    /// Application Support/Scanner/Documents/<UUID>/pages/
    @discardableResult
    public func pagesDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let url = try documentRootURL(fileManager: fileManager)
            .appendingPathComponent("pages", isDirectory: true)
        return try ScannerPaths.ensureDirectoryURL(url, fileManager: fileManager)
    }

    /// Application Support/Scanner/Documents/<UUID>/output/
    @discardableResult
    public func outputDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let url = try documentRootURL(fileManager: fileManager)
            .appendingPathComponent("output", isDirectory: true)
        return try ScannerPaths.ensureDirectoryURL(url, fileManager: fileManager)
    }

    // Section 2.6 Output PDF URL
    /// Application Support/Scanner/Documents/<UUID>/output/document.pdf
    public func pdfURL(fileManager: FileManager = .default) throws -> URL {
        return try outputDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("document.pdf", isDirectory: false)
    }

    // Section 2.7 Page image URL helpers
    /// Application Support/Scanner/Documents/<UUID>/pages/001.jpg, 002.jpg, ...
    public func pageImageURL(pageIndex: Int, fileManager: FileManager = .default) throws -> URL {
        let pagesDir = try pagesDirectoryURL(fileManager: fileManager)
        let filename = String(format: "%03d.jpg", pageIndex)
        return pagesDir.appendingPathComponent(filename, isDirectory: false)
    }

    /// 1-based index convenience (pageNumber: 1 => 001.jpg)
    public func pageImageURL(pageNumber: Int, fileManager: FileManager = .default) throws -> URL {
        return try pageImageURL(pageIndex: pageNumber, fileManager: fileManager)
    }
}

// ScannerDocumentPaths.swift

// ScannerDocumentMetadata.swift
// File: ScannerDocumentMetadata.swift
// Description:
// Codable metadata model for ScannerKit documents.
// - Persisted as JSON at Application Support/Scanner/Documents/<UUID>/metadata.json
// - Used by Library listing, document lifecycle state, and CloudKit mapping.
//
// Interactions:
// - Written by ScannerDraftPersistence when creating drafts.
// - Read later by a Library indexer / document store.
// - Document directory layout is defined by ScannerDocumentPaths.
//
// Debug Logging:
// - No direct logging here; call sites should log reads/writes.
//
// Section 1. Imports
import Foundation

// Section 2. Document State
public enum ScannerDocumentState: String, Codable {
    case draft
    case savedLocal
    case syncing
    case synced
    case syncError
}

// Section 3. ScannerDocumentMetadata
public struct ScannerDocumentMetadata: Codable, Identifiable {

    // Section 3.1 Identity
    public var id: UUID { documentID }
    public let documentID: UUID

    // Section 3.2 User-facing
    public var title: String

    // Section 3.3 Timestamps
    public let createdAt: Date
    public var modifiedAt: Date

    // Section 3.4 Content
    public var pageCount: Int
    public var state: ScannerDocumentState

    // Section 3.5 Init
    public init(
        documentID: UUID,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        pageCount: Int,
        state: ScannerDocumentState
    ) {
        self.documentID = documentID
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pageCount = pageCount
        self.state = state
    }
}

// End of file: ScannerDocumentMetadata.swift

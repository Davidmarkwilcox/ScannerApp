// ScannedPage.swift
// File: ScannedPage.swift
// Description:
// Core model representing a single scanned page captured by the document camera.
// This model is intentionally lightweight and UI-agnostic so it can live in ScannerKit
// and be lifted into a standalone ScannerKit repository later with no refactoring.
//
// Section 1. Imports
import Foundation
import UIKit

// Section 2. Model
public struct ScannedPage: Identifiable, Hashable {

    // Section 2.1 Properties
    public let id: UUID
    public let pageIndex: Int
    public let image: UIImage
    public let createdAt: Date

    // Section 2.2 Initializer
    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        image: UIImage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.image = image
        self.createdAt = createdAt
    }

    // Section 2.3 Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ScannedPage, rhs: ScannedPage) -> Bool {
        lhs.id == rhs.id
    }
}

// End of file: ScannedPage.swift

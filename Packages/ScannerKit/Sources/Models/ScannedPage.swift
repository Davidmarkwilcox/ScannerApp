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

    // Section 2.4 Transforms
    /// Returns a new `ScannedPage` with its image rotated 90°.
    /// - Note: Keeps `id`, `pageIndex`, and `createdAt` identical; only the image changes.
    public func rotated90(clockwise: Bool = true) -> ScannedPage {
        ScannedPage(
            id: id,
            pageIndex: pageIndex,
            image: image.scannerkit_rotated90(clockwise: clockwise),
            createdAt: createdAt
        )
    }

    /// Returns a copy of `pages` with `pageIndex` rewritten to match array order (0...n-1).
    /// - Note: Preserves each page's `id`, `image`, and `createdAt`.
    public static func reindexed(_ pages: [ScannedPage]) -> [ScannedPage] {
        pages.enumerated().map { (idx, page) in
            ScannedPage(id: page.id, pageIndex: idx, image: page.image, createdAt: page.createdAt)
        }
    }
}

// Section 3. UIImage helpers (ScannerKit-internal)
private extension UIImage {

    /// Rotates the image 90° clockwise/counterclockwise.
    /// - Important: Uses the image's scale and returns an upright image.
    func scannerkit_rotated90(clockwise: Bool) -> UIImage {
        let radians: CGFloat = clockwise ? (.pi / 2) : (-.pi / 2)
        let newSize = CGSize(width: size.height, height: size.width)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            // Move origin to center so rotation happens around center.
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)

            // After rotation, draw original image centered.
            ctx.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// End of file: ScannedPage.swift

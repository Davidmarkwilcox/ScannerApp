// DocumentCameraCoordinator.swift
// File: DocumentCameraCoordinator.swift
// Description:
// Coordinator/delegate for VNDocumentCameraViewController. Converts VisionKit output into ScannerKit models.
// Kept separate to make DocumentCamera.swift small and easy to reason about.
//
// Section 1. Imports
import Foundation
import VisionKit
import UIKit

// Section 2. Coordinator
public final class DocumentCameraCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {

    // Section 2.1 State
    private let preset: ScanPreset
    private let onResult: (DocumentCameraResult) -> Void

    // If the device is not supported, DocumentCamera sets this before presentation.
    // We’ll fail once the controller appears (via delegate callbacks when dismissed).
    internal var deferImmediateFailure: Error? = nil

    // Section 2.2 Init
    public init(preset: ScanPreset, onResult: @escaping (DocumentCameraResult) -> Void) {
        self.preset = preset
        self.onResult = onResult
    }

    // Section 2.3 Cancel
    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true) {
            if let error = self.deferImmediateFailure {
                self.onResult(.failure(error: error))
            } else {
                self.onResult(.cancelled)
            }
        }
    }

    // Section 2.4 Error
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true) {
            self.onResult(.failure(error: error))
        }
    }

    // Section 2.5 Success
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        // Convert scanned pages to ScannedPage models
        var pages: [ScannedPage] = []
        pages.reserveCapacity(scan.pageCount)

        for index in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: index)
            let processed = Self.applyPreset(preset, to: image)
            pages.append(ScannedPage(pageIndex: index, image: processed))
        }

        controller.dismiss(animated: true) {
            self.onResult(.success(pages: pages))
        }
    }


    // Section 2.6 Preset application
    private static func applyPreset(_ preset: ScanPreset, to image: UIImage) -> UIImage {
        let maxDim = preset.maxPixelDimension
        guard maxDim > 0 else { return image }

        let resized = resize(image: image, maxPixelDimension: maxDim) ?? image

        // Re-encode to JPEG to further reduce footprint for lower presets (optional but effective).
        // Note: This is a lossy operation by design for "Fast" / "Balanced".
        if let data = resized.jpegData(compressionQuality: preset.jpegQuality),
           let decoded = UIImage(data: data, scale: resized.scale) {
            return decoded
        }

        return resized
    }

    private static func resize(image: UIImage, maxPixelDimension: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longest = max(size.width, size.height)
        guard longest > maxPixelDimension else { return image }

        let scale = maxPixelDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // work in pixel-ish space; jpegData will handle final encoding
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let output = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return output
    }

}

// End of file: DocumentCameraCoordinator.swift

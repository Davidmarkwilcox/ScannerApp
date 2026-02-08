// DocumentCameraCoordinator.swift
// File: DocumentCameraCoordinator.swift
// Description:
// Coordinator/delegate for VNDocumentCameraViewController. Converts VisionKit output into ScannerKit models.
// Kept separate to make DocumentCamera.swift small and easy to reason about.
//
// Section 1. Imports
import Foundation
import VisionKit

// Section 2. Coordinator
public final class DocumentCameraCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {

    // Section 2.1 State
    private let onResult: (DocumentCameraResult) -> Void

    // If the device is not supported, DocumentCamera sets this before presentation.
    // We’ll fail once the controller appears (via delegate callbacks when dismissed).
    internal var deferImmediateFailure: Error? = nil

    // Section 2.2 Init
    public init(onResult: @escaping (DocumentCameraResult) -> Void) {
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
            pages.append(ScannedPage(pageIndex: index, image: image))
        }

        controller.dismiss(animated: true) {
            self.onResult(.success(pages: pages))
        }
    }
}

// End of file: DocumentCameraCoordinator.swift

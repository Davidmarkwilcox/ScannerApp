// DocumentCamera.swift
// File: DocumentCamera.swift
// Description:
// SwiftUI wrapper for VisionKit's VNDocumentCameraViewController.
// Lives in ScannerKit so ScannerApp can remain a thin UI shell.
// Designed for “lift-and-shift” into a standalone ScannerKit repo later.
//
// Section 1. Imports
import SwiftUI
import UIKit
import VisionKit

// Section 2. Errors
public enum DocumentCameraError: Error, LocalizedError {
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Document scanning is not supported on this device."
        }
    }
}

// Section 3. Result
public enum DocumentCameraResult {
    case success(pages: [ScannedPage])
    case cancelled
    case failure(error: Error)
}

// Section 4. SwiftUI wrapper
public struct DocumentCamera: UIViewControllerRepresentable {

    // Section 4.1 Callback
    private let onResult: (DocumentCameraResult) -> Void

    // Section 4.2 Init
    public init(onResult: @escaping (DocumentCameraResult) -> Void) {
        self.onResult = onResult
    }

    // Section 4.3 Make VC
    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        // Device capability check (VisionKit requirement)
        guard VNDocumentCameraViewController.isSupported else {
            // We can’t throw from makeUIViewController; return a controller anyway and fail on appear.
            // Coordinator will immediately dismiss if presented.
            let vc = VNDocumentCameraViewController()
            context.coordinator.deferImmediateFailure = DocumentCameraError.notSupported
            return vc
        }

        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    // Section 4.4 Update
    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No-op
    }

    // Section 4.5 Coordinator
    public func makeCoordinator() -> DocumentCameraCoordinator {
        DocumentCameraCoordinator(onResult: onResult)
    }
}

// End of file: DocumentCamera.swift

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


// Section 3. Scan Preset
public enum ScanPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case quality = "Quality"

    public var id: String { rawValue }

    // Max pixel dimension for the longest side (0 = no resize)
    internal var maxPixelDimension: CGFloat {
        switch self {
        case .fast: return 1600
        case .balanced: return 2400
        case .quality: return 0
        }
    }

    // JPEG compression quality (0...1). Used only when resizing/compressing.
    internal var jpegQuality: CGFloat {
        switch self {
        case .fast: return 0.60
        case .balanced: return 0.80
        case .quality: return 0.92
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
    private let preset: ScanPreset

    private let onResult: (DocumentCameraResult) -> Void

    // Section 4.2 Init
    public init(preset: ScanPreset = .balanced, onResult: @escaping (DocumentCameraResult) -> Void) {
        self.preset = preset
        self.onResult = onResult
    }

    // Convenience init for callers storing presets as raw strings (e.g., AppStorage)
    public init(presetRawValue: String, onResult: @escaping (DocumentCameraResult) -> Void) {
        self.preset = ScanPreset(rawValue: presetRawValue) ?? .balanced
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
        DocumentCameraCoordinator(preset: preset, onResult: onResult)
    }
}

// End of file: DocumentCamera.swift

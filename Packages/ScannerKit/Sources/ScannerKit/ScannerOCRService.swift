// ScannerOCRService.swift
// File: ScannerOCRService.swift
// Description:
// On-device OCR (text recognition) service for ScannerKit using Apple Vision.
// - Recognizes text from one or more `ScannedPage` images.
// - Returns per-page text and a concatenated fullText.
// - Does NOT automatically persist results; persist via `ScannerDraftPersistence.saveOCRResult(...)`.
//
// Interactions:
// - Called from ScannerApp UI (e.g., ReviewView) to run manual OCR.
// - Pairs with ScannerDraftPersistence OCR helpers to store results under each document directory.
//
// Debug Logging:
// - Default debug mode is Off.
// - Enable via ScannerOCRService.setDebugEnabled(true).
//
// Section 1. Imports
import Foundation
import Vision
import UIKit

// Section 2. OCR Service
public enum ScannerOCRService {

    // Section 2.1 Debug toggle (default Off)
    private static var isDebugEnabled: Bool = false

    public static func setDebugEnabled(_ enabled: Bool) {
        isDebugEnabled = enabled
    }

    // Section 2.2 Result type
    public struct OCRResult: Sendable, Equatable {
        public let fullText: String
        public let perPageText: [Int: String]

        public init(fullText: String, perPageText: [Int: String]) {
            self.fullText = fullText
            self.perPageText = perPageText
        }
    }

    // Section 2.3 Errors
    public enum OCRError: Error, LocalizedError {
        case emptyPages
        case imageConversionFailed(pageIndex: Int)

        public var errorDescription: String? {
            switch self {
            case .emptyPages:
                return "Cannot run OCR: pages array is empty."
            case .imageConversionFailed(let pageIndex):
                return "OCR failed: could not convert page \(pageIndex + 1) image for recognition."
            }
        }
    }

    // Section 2.4 Public API
    /// Recognize text for each page (sequentially), returning a per-page map and a concatenated `fullText`.
    /// - Parameters:
    ///   - pages: Pages to OCR.
    ///   - recognitionLevel: `.accurate` (default) or `.fast`.
    ///   - languages: Optional BCP-47 language codes. If nil, Vision auto-detects.
    ///   - usesLanguageCorrection: Enables Vision language correction.
    public static func recognizeText(
        pages: [ScannedPage],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        languages: [String]? = nil,
        usesLanguageCorrection: Bool = true
    ) async throws -> OCRResult {

        guard !pages.isEmpty else { throw OCRError.emptyPages }

        var perPage: [Int: String] = [:]
        perPage.reserveCapacity(pages.count)

        for (idx, page) in pages.enumerated() {
            try Task.checkCancellation()

            debugLog("Recognizing page \(idx + 1)/\(pages.count) id=\(page.id.uuidString)")

            guard let cgImage = page.image.cgImage else {
                throw OCRError.imageConversionFailed(pageIndex: idx)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            let recognized = try await recognizeText(with: handler, recognitionLevel: recognitionLevel, languages: languages, usesLanguageCorrection: usesLanguageCorrection)
            perPage[idx] = recognized

            debugLog("Page \(idx + 1) chars=\(recognized.count)")
        }

        let fullText = pages
            .enumerated()
            .map { (idx, _) in perPage[idx] ?? "" }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        debugLog("OCR complete pages=\(pages.count) fullChars=\(fullText.count)")

        return OCRResult(fullText: fullText, perPageText: perPage)
    }

    // Section 2.5 Internal recognition
    private static func recognizeText(
        with handler: VNImageRequestHandler,
        recognitionLevel: VNRequestTextRecognitionLevel,
        languages: [String]?,
        usesLanguageCorrection: Bool
    ) async throws -> String {

        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []

                // Take best candidate per observation, then join by newlines.
                let lines: [String] = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }

                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection

            if let languages = languages, !languages.isEmpty {
                request.recognitionLanguages = languages
            }

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // Section 2.6 Debug logging helper
    private static func debugLog(_ message: String) {
        guard isDebugEnabled else { return }
        print("ScannerOCRService: \(message)")
    }
}

// End of file: ScannerOCRService.swift

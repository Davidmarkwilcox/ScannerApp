// ScanView.swift
// File: ScanView.swift
// Description:
// Scan screen for ScannerApp. Presents ScannerKit's DocumentCamera (VisionKit document capture),
// receives captured pages as [ScannerKit.ScannedPage], and hands off captured pages to ReviewView.
// UI styling uses Theme; scanning logic remains in ScannerKit for lift-and-shift safety.
//
// Section 1. Imports
import SwiftUI
import UIKit
import PhotosUI
import ScannerKit

// Section 2. View
struct ScanView: View {

    // Section 2.1 State
    @AppStorage("scanner.scanPreset") private var scanPresetRaw: String = "Balanced"

    @State private var isPresentingCamera: Bool = false

    // Section 2.1.1 Import (Photos)
    @State private var isPresentingPhotoPicker: Bool = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

    @State private var scannedPages: [ScannerKit.ScannedPage] = []
    @State private var lastErrorMessage: String? = nil
    @State private var navigateToReview: Bool = false

    // Section 2.2 Body
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {

            // Section 2.2.1 Header
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Scan")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Capture one or more pages using the document camera.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scannerGlassCard(padding: Theme.Spacing.lg)

            // Section 2.2.2 Actions
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Actions")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Button {
                    lastErrorMessage = nil
                    isPresentingCamera = true
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: present DocumentCamera (preset=\(scanPresetRaw))") }
                } label: {
                    Label("Scan Document", systemImage: "camera.viewfinder")
                }
                .buttonStyle(ScannerPrimaryButtonStyle())

                Button {
                    lastErrorMessage = nil
                    isPresentingPhotoPicker = true
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: present PhotosPicker") }
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(ScannerPrimaryButtonStyle())

                // Section 2.2.3 Review navigation (enabled when pages exist)
                NavigationLink(isActive: $navigateToReview) {
                    ReviewView(pages: scannedPages)
                } label: {
                    EmptyView()
                }

                Button {
                    navigateToReview = true
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: navigate to Review") }
                } label: {
                    Label("Go to Review", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .disabled(scannedPages.isEmpty)

                if scannedPages.isEmpty == false {
                    Text("Captured pages: \(scannedPages.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .transition(.opacity)
                }

                if let lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .transition(.opacity)
                }

            }
            .scannerGlassCard(padding: Theme.Spacing.lg)
            .animation(Theme.Motion.standard, value: scannedPages.count)
            .animation(Theme.Motion.standard, value: lastErrorMessage)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .scannerScreen()
        .navigationTitle("Scan")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView appeared") }
        }
        .sheet(isPresented: $isPresentingCamera) {
            DocumentCamera(presetRawValue: scanPresetRaw) { result in
                switch result {
                case .success(let pages):
                    // Normalize to ScannerKit.ScannedPage to avoid module-type collisions
                    let newPages: [ScannerKit.ScannedPage] = pages.map { page in
                        ScannerKit.ScannedPage(id: page.id, pageIndex: page.pageIndex, image: page.image, createdAt: page.createdAt)
                    }

                    let beforeCount = scannedPages.count
                    scannedPages.append(contentsOf: newPages)
                    scannedPages = ScannerKit.ScannedPage.reindexed(scannedPages)

                    lastErrorMessage = nil
                    if ScannerDebug.isEnabled {
                        ScannerDebug.writeLog("ScanView: captured \(newPages.count) pages (before=\(beforeCount) total=\(scannedPages.count))")
                    }

                case .cancelled:
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: camera cancelled") }

                case .failure(let error):
                    lastErrorMessage = error.localizedDescription
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: camera failed: \(error.localizedDescription)") }
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $photoPickerItems,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importSelectedPhotos(items: newItems) }
        }
    }

    // Section 2.3 Import helpers
    @MainActor
    private func importSelectedPhotos(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        let startIndex = scannedPages.count
        var imported: [ScannerKit.ScannedPage] = []
        var failedCount: Int = 0

        for (offset, item) in items.enumerated() {
            do {
                // Prefer Data to avoid forcing a specific image representation.
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {

                    let page = ScannerKit.ScannedPage(
                        id: UUID(),
                        pageIndex: startIndex + offset,
                        image: image,
                        createdAt: Date()
                    )
                    imported.append(page)
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
                if ScannerDebug.isEnabled {
                    ScannerDebug.writeLog("ScanView: import failed: \(error.localizedDescription)")
                }
            }
        }

        // Clear selection so a user can re-import the same items later if needed.
        photoPickerItems = []

        guard !imported.isEmpty else {
            lastErrorMessage = "Import failed. No images could be imported." + (failedCount > 0 ? " (Failed: \(failedCount))" : "")
            return
        }

        scannedPages.append(contentsOf: imported)
        scannedPages = ScannerKit.ScannedPage.reindexed(scannedPages)

        if failedCount > 0 {
            lastErrorMessage = "Imported \(imported.count) image(s). Failed: \(failedCount)."
        } else {
            lastErrorMessage = nil
        }

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("ScanView: imported \(imported.count) image(s), failed=\(failedCount), total=\(scannedPages.count)")
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { ScanView() }
}

// End of file: ScanView.swift

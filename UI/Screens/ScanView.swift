// ScanView.swift
// File: ScanView.swift
// Description:
// Scan screen for ScannerApp. Presents ScannerKit's DocumentCamera (VisionKit document capture),
// receives captured pages as [ScannerKit.ScannedPage], and hands off captured pages to ReviewView.
// UI styling uses Theme; scanning logic remains in ScannerKit for lift-and-shift safety.
//
// Section 1. Imports
import SwiftUI
import ScannerKit

// Section 2. View
struct ScanView: View {

    // Section 2.1 State
    @State private var isPresentingCamera: Bool = false
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
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: present DocumentCamera") }
                } label: {
                    Label("Scan Document", systemImage: "camera.viewfinder")
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

                Text("Next: crop/reorder + draft persistence (Application Support/Scanner/Documents/<UUID>/...).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
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
            DocumentCamera { result in
                switch result {
                case .success(let pages):
                    // Normalize to ScannerKit.ScannedPage to avoid module-type collisions
                    scannedPages = pages.map { page in
                        ScannerKit.ScannedPage(id: page.id, pageIndex: page.pageIndex, image: page.image, createdAt: page.createdAt)
                    }
                    lastErrorMessage = nil
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: captured \(scannedPages.count) pages") }

                case .cancelled:
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: camera cancelled") }

                case .failure(let error):
                    lastErrorMessage = error.localizedDescription
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: camera failed: \(error.localizedDescription)") }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { ScanView() }
}

// End of file: ScanView.swift

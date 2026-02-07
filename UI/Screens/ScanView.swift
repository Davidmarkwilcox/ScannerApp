// ScanView.swift
// File: ScanView.swift
// Description: Placeholder Scan screen. Eventually hosts camera capture + edge detection and multi-page capture.
// Styled with Theme defaults.
//
// Section 1. Imports
import SwiftUI

// Section 2. View
struct ScanView: View {

    // Section 2.1 State
    @State private var isSimulatingScan: Bool = false

    // Section 2.2 Body
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Scan")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Placeholder screen. This will host camera scanning and multi-page capture.")
                    .font(Theme.Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scannerGlassCard(padding: Theme.Spacing.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Actions")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Button {
                    isSimulatingScan.toggle()
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView: simulateScan tapped") }
                } label: {
                    Label(isSimulatingScan ? "Simulated Scan Started" : "Simulate Scan",
                          systemImage: "camera")
                }
                .buttonStyle(ScannerPrimaryButtonStyle())

                Text("Next: wire VisionKit scanning into this screen (or ScannerKit abstraction).")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .scannerGlassCard(padding: Theme.Spacing.lg)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .scannerScreen()
        .navigationTitle("Scan")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ScanView appeared") }
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { ScanView() }
}

// End of file: ScanView.swift

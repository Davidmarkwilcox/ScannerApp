// ReviewView.swift
// File: ReviewView.swift
// Description: Placeholder Review screen. Eventually provides crop/rotate, page ordering, filters, and naming.
// Styled with Theme defaults.
//
// Section 1. Imports
import SwiftUI

// Section 2. View
struct ReviewView: View {

    // Section 2.1 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.1.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Review")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Placeholder screen. Review/edit pages before saving/exporting.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.1.2 Next
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Next")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    NavigationLink {
                        ViewerView()
                    } label: {
                        Label("Proceed to Viewer", systemImage: "chevron.right")
                            .font(Theme.Typography.body)
                    }
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.1.3 Planned tools
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Planned Review Tools")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label("Crop / perspective", systemImage: "crop")
                        Label("Rotate", systemImage: "rotate.right")
                        Label("Reorder pages", systemImage: "arrow.up.arrow.down")
                        Label("Filters / B&W", systemImage: "camera.filters")
                        Label("Name default: Scan-YYYYMMDDHHMMSS", systemImage: "pencil")
                    }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)
            }
            .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Review")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ReviewView appeared") }
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { ReviewView() }
}

// End of file: ReviewView.swift

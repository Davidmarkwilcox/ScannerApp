// ReviewView.swift
// File: ReviewView.swift
// Description:
// Review screen for ScannerApp. Displays captured pages from ScannerKit as thumbnails and basic metadata.
// This is the first real handoff step from Scan -> Review. Next iterations will add crop/rotate/reorder,
// and draft persistence.
//
// Section 1. Imports
import SwiftUI
import ScannerKit

// Section 2. View
struct ReviewView: View {

    // Section 2.1 Inputs
    let pages: [ScannedPage]

    // Section 2.2 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.2.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Review")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Confirm pages before saving/exporting.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Pages: \(pages.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.2.2 Thumbnails
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Captured Pages")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if pages.isEmpty {
                        Text("No pages captured yet.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        // Simple grid for now. (We’ll refine to reorder + delete later.)
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: Theme.Spacing.md),
                            GridItem(.flexible(), spacing: Theme.Spacing.md)
                        ], spacing: Theme.Spacing.md) {
                            ForEach(pages) { page in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Image(uiImage: page.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 160)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous)
                                                .stroke(Theme.Colors.glassStroke.opacity(0.35), lineWidth: 1)
                                        )

                                    Text("Page \(page.pageIndex + 1)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.2.3 Next steps (placeholder)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Next")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Label("Crop / perspective", systemImage: "crop")
                    Label("Rotate", systemImage: "rotate.right")
                    Label("Reorder pages", systemImage: "arrow.up.arrow.down")
                    Label("Delete / retake", systemImage: "trash")
                    Label("Name draft + save PDF", systemImage: "doc.badge.plus")
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .scannerGlassCard(padding: Theme.Spacing.lg)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Review")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ReviewView appeared with \(pages.count) pages") }
        }
    }
}

// Section 3. Preview
#Preview {
    // Preview uses an empty pages array to avoid embedding sample images.
    NavigationStack { ReviewView(pages: []) }
}

// End of file: ReviewView.swift

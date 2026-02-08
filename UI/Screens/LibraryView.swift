// LibraryView.swift
// File: LibraryView.swift
// Description: Placeholder Library screen. Eventually lists documents with thumbnails, unsaved indicators,
// and actions (open/view/share/save/delete). Styled with Theme defaults.
//
// Section 1. Imports
import SwiftUI

// Section 2. View
struct LibraryView: View {

    // Section 2.1 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.1.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Library")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Placeholder screen. This will list scans with thumbnails and status indicators.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.1.2 Navigation stubs
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Navigation Stubs")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    NavigationLink {
                        ViewerView()
                    } label: {
                        Label("Go to Viewer", systemImage: "doc.text.magnifyingglass")
                            .font(Theme.Typography.body)
                    }
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.1.3 Roadmap
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Upcoming")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label("Multi-page documents", systemImage: "doc.richtext")
                        Label("Sandbox storage + save/share", systemImage: "folder")
                        Label("Unsaved indicator", systemImage: "exclamationmark.circle")
                        Label("Delete with confirmation", systemImage: "trash")
                        Label("Cloud sync (scans + settings)", systemImage: "icloud")
                    }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)
            }
            .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Library")
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("LibraryView appeared") }
        }
    }
}

// Section 3. Preview
#Preview {
    NavigationStack { LibraryView() }
}

// End of file: LibraryView.swift

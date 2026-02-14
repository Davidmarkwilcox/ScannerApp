// ReviewView.swift
// File: ReviewView.swift
// Description:
// Review screen for ScannerApp.
// - Displays captured pages from ScannerKit.
// - Provides review tools (Option 2): reorder, delete, rotate.
// ScannerKit owns manipulation transforms; ScannerApp owns UI/state.
//
// NOTE (2026-02-11): ScannerKitUI has been removed. This file now uses a ScannerApp-local
// full-screen viewer placeholder (LocalPageViewerPlaceholder) until the SwiftUI-native
// zoom/expand viewer is rebuilt inside ScannerApp.
//
// Section 1. Imports
import SwiftUI
import UIKit
import ScannerKit

// Section 2. View
struct ReviewView: View {

    // Section 2.1 State (UI-owned)
    @State private var pages: [ScannerKit.ScannedPage]
    @State private var selectedPage: ScannerKit.ScannedPage? = nil

    // Section 2.1.0 Document identity
    @State private var currentDocumentID: UUID? = nil

    // Section 2.1.1 Save Draft UI state
    @State private var isShowingSaveDraftAlert: Bool = false
    @State private var saveDraftAlertTitle: String = ""
    @State private var saveDraftAlertMessage: String = ""


    // Section 2.1.2 Export/Share UI state
    // NOTE: We present the share sheet via UIKit directly to avoid SwiftUI sheet timing/state edge-cases.
    // (Keeping this section placeholder for future UI-driven share flows.)

    // Section 2.2 Environment
    @Environment(\.editMode) private var editMode

    // Section 2.3 Init
    init(pages: [ScannerKit.ScannedPage]) {
        _pages = State(initialValue: pages)
    }

    // Section 2.4 Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                // Section 2.4.1 Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Review")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Reorder, rotate, or delete pages before saving/exporting.")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Pages: \(pages.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                // Section 2.4.2 Pages list (reorder/delete/rotate)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Captured Pages")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        // Small status indicator when in edit mode.
                        if editMode?.wrappedValue.isEditing == true {
                            Text("Editing")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    if pages.isEmpty {
                        Text("No pages captured yet.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        List {
                            ForEach(pages) { page in
                                ReviewPageRow(
                                    page: page,
                                    isEditing: editMode?.wrappedValue.isEditing == true,
                                    onRotateClockwise: { rotate(pageID: page.id, clockwise: true) },
                                    onRotateCounterClockwise: { rotate(pageID: page.id, clockwise: false) },
                                    onTap: { selectedPage = page }
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .onMove(perform: movePages)
                            .onDelete(perform: deletePages)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: min(520, CGFloat(pages.count) * 92.0))
                        .environment(\.defaultMinListRowHeight, 84)
                    }
                }
                .scannerGlassCard(padding: Theme.Spacing.lg)

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Review")
        .toolbar { reviewToolbar }
        .fullScreenCover(item: $selectedPage) { page in
            // Section 2.5 Full-screen viewer (ScannerApp-local placeholder)
            LocalPageViewerPlaceholder(page: page) {
                selectedPage = nil
            }
        }

        .alert(saveDraftAlertTitle, isPresented: $isShowingSaveDraftAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveDraftAlertMessage)
        }
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ReviewView appeared with \(pages.count) pages") }
        }
    }

    // Section 3. Toolbar
    @ToolbarContentBuilder
    private var reviewToolbar: some ToolbarContent {
        // Section 3.1 Save Draft
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                saveDraft()
            } label: {
                Label("Save Draft", systemImage: "tray.and.arrow.down")
            }
            .tint(Theme.Colors.textPrimary)
            .disabled(pages.isEmpty)
        }

        // Section 3.2 Export PDF + Share
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                exportPDFAndShare()
            } label: {
                Label("Share PDF", systemImage: "square.and.arrow.up")
            }
            .tint(Theme.Colors.textPrimary)
            .disabled(pages.isEmpty)
        }

        // Section 3.3 Edit (reorder/delete)
        ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
                .tint(Theme.Colors.textPrimary)
        }
    }

    // Section 4. Actions (UI invokes ScannerKit transforms)
    private func saveDraft() {
        do {
            let result = try ScannerDraftPersistence.saveDraft(documentID: currentDocumentID, pages: pages)
            currentDocumentID = result.documentID

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("Saved draft documentID=\(result.documentID.uuidString) pages=\(result.pageCount) root=\(result.documentRootURL.path)")
            }

            saveDraftAlertTitle = "Draft Saved"
            saveDraftAlertMessage = "Saved \(result.pageCount) page(s).\n\nDocument ID:\n\(result.documentID.uuidString)"

            isShowingSaveDraftAlert = true
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("Save draft failed: \(error.localizedDescription)")
            }

            saveDraftAlertTitle = "Save Failed"
            saveDraftAlertMessage = error.localizedDescription
            isShowingSaveDraftAlert = true
        }
    }


    private func exportPDFAndShare() {
        do {
            let fileManager = FileManager.default

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] Share tapped. documentID=\(currentDocumentID?.uuidString ?? "nil") pages=\(pages.count)")
            }

            // Ensure we have a persisted document ID (draft) so ScannerKit can generate a shareable PDF.
            let result = try ScannerDraftPersistence.saveDraft(documentID: currentDocumentID, pages: pages)
            currentDocumentID = result.documentID

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] saveDraft ok. documentID=\(result.documentID.uuidString) pages=\(result.pageCount)")
            }

            // IMPORTANT:
            // Share must work on the first save cycle. Use ScannerKit's "pdfURLForSharing" helper which:
            // - returns output/document.pdf if it already exists, OR
            // - generates it from persisted page JPEGs and updates metadata to savedLocal.
            let pdfURL = try ScannerDraftPersistence.pdfURLForSharing(
                documentID: result.documentID,
                fileManager: fileManager
            )

            // Diagnostics: validate existence + size to avoid silent share-sheet no-ops.
            let exists = fileManager.fileExists(atPath: pdfURL.path)
            let fileSize: Int64 = (try? fileManager.attributesOfItem(atPath: pdfURL.path)[.size] as? Int64) ?? -1

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] PDF ready. exists=\(exists) size=\(fileSize) url=\(pdfURL.lastPathComponent)")
            }

            guard exists, fileSize > 0 else {
                throw NSError(
                    domain: "ReviewView",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed: PDF missing or empty at expected path: \(pdfURL.lastPathComponent) (exists=\(exists) size=\(fileSize))"]
                )
            }

            // Present share sheet on the next run-loop tick to avoid UIKit presentation timing edge-cases.
            DispatchQueue.main.async {
                self.presentShareSheet(url: pdfURL, documentID: result.documentID)
            }

        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] Export/share failed: \(error.localizedDescription)")
            }

            saveDraftAlertTitle = "Export Failed"
            saveDraftAlertMessage = error.localizedDescription
            isShowingSaveDraftAlert = true
        }
    }


    private func rotate(pageID: UUID, clockwise: Bool) {
        guard let idx = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[idx] = pages[idx].rotated90(clockwise: clockwise)

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Rotated page id=\(pageID) clockwise=\(clockwise)")
        }
    }

    private func deletePages(at offsets: IndexSet) {
        pages.remove(atOffsets: offsets)
        pages = ScannerKit.ScannedPage.reindexed(pages)

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Deleted pages at offsets=\(Array(offsets)) -> remaining=\(pages.count)")
        }
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        pages = ScannerKit.ScannedPage.reindexed(pages)

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Moved pages from=\(Array(source)) to=\(destination)")
        }
    }


    // Section 4.2 Share Presentation (UIKit)
    private func presentShareSheet(url: URL, documentID: UUID) {
        // Find the top-most view controller in the active foreground scene.
        guard let topVC = ReviewViewTopMostViewControllerResolver.topMostViewController() else {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] ERROR: Unable to resolve top-most UIViewController for share presentation")
            }
            saveDraftAlertTitle = "Export Failed"
            saveDraftAlertMessage = "Unable to present share sheet (no active view controller)."
            isShowingSaveDraftAlert = true
            return
        }

        if ScannerDebug.isEnabled {
            let presented = topVC.presentedViewController.map { String(describing: type(of: $0)) } ?? "nil"
            ScannerDebug.writeLog("[ReviewView] Presenting share sheet. documentID=\(documentID.uuidString) presenter=\(String(describing: type(of: topVC))) alreadyPresented=\(presented)")
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPhone: no popover config required.
        topVC.present(activityVC, animated: true)
    }
}

// Section 5. Row
private struct ReviewPageRow: View {

    // Section 5.1 Inputs
    let page: ScannerKit.ScannedPage
    let isEditing: Bool
    let onRotateClockwise: () -> Void
    let onRotateCounterClockwise: () -> Void
    let onTap: () -> Void

    // Section 5.2 Body
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {

            // Thumbnail
            Image(uiImage: page.image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 84)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Corners.card, style: .continuous)
                        .stroke(Theme.Colors.glassStroke.opacity(0.35), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Page \(page.pageIndex + 1)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(page.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            // Rotate controls stay available even in Edit mode.
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onRotateCounterClockwise) {
                    Image(systemName: "rotate.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityLabel("Rotate counterclockwise")

                Button(action: onRotateClockwise) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityLabel("Rotate clockwise")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            // Use Theme's existing frosted approach without inventing new tokens.
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Corners.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Corners.chip, style: .continuous)
                    .stroke(Theme.Colors.glassStroke.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            onTap()
        }
        .opacity(isEditing ? 0.98 : 1.0)
    }
}

// Section 6. ScannerApp-local placeholder viewer (temporary)
private struct LocalPageViewerPlaceholder: View {
    let page: ScannerKit.ScannedPage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            // Basic viewing: no zoom yet (intentionally).
            Image(uiImage: page.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            Button(action: {
                if ScannerDebug.isEnabled { ScannerDebug.writeLog("Closed placeholder viewer for page id=\(page.id)") }
                onClose()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
            .accessibilityLabel("Close page viewer")
        }
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("Opened placeholder viewer for page id=\(page.id)") }
        }
    }
}


// Section 6.1 Top-most view controller resolver (UIKit)
private enum ReviewViewTopMostViewControllerResolver {

    static func topMostViewController() -> UIViewController? {
        // Active foreground window scene.
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        guard let root = windowScene?.keyWindow?.rootViewController else { return nil }
        return topMost(from: root)
    }

    private static func topMost(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = vc as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        return vc
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: { $0.isKeyWindow })
    }
}

// Section 7. Preview
#Preview {
    // Preview uses an empty pages array to avoid embedding sample images.
    NavigationStack { ReviewView(pages: []) }
}

// End of file: ReviewView.swift

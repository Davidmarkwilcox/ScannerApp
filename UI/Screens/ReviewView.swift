// ReviewView.swift
// File: ReviewView.swift
// Description:
// Review screen for ScannerApp.
// - Displays captured pages from ScannerKit.
// - Provides review tools: reorder, delete, rotate.
// - Presents ViewerView full-screen for zoom/rotate viewing.
//
// Notes:
// - Review owns UI state; ScannerKit owns image transforms (rotated90).
// - `viewerRefreshToken` is bumped after mutations to force SwiftUI to refresh thumbnails and viewer images.
//
// Section 1. Imports
import SwiftUI
import UIKit
import ScannerKit

// Section 2. View
struct ReviewView: View {

    // Section 2.1 State (UI-owned)
    @AppStorage("scanner.scanPreset") private var scanPresetRaw: String = "Balanced"

    @State private var isPresentingCamera: Bool = false
    @State private var pages: [ScannerKit.ScannedPage]

    /// Selected page index for full-screen viewer presentation.
    @State private var selectedPageIndex: Int? = nil

    /// Refresh token for ViewerView + row thumbnails (workaround for SwiftUI image caching).
    @State private var viewerRefreshToken: Int = 0


    /// Track whether edits (rotate/reorder/delete/add) have occurred since last persistence.
    @State private var hasUnsavedEdits: Bool = false

    // Section 2.1.3 OCR UI state
    @State private var isRecognizingText: Bool = false
    @State private var lastRecognizedText: String = ""

    // Section 2.1.4 Entity detection UI state
    @State private var isShowingEntityActions: Bool = false
    @State private var detectedEntities: [DetectedEntity] = []

    // Section 2.1.2 Layout constants (Captured Pages container)
    private let pagesListVisibleRowsMin: Int = 1
    private let pagesListVisibleRowsMax: Int = 4
    /// Approximate row height for a single page row (thumbnail + labels + actions).
    private let pagesListRowHeight: CGFloat = 118
    /// Small extra height to avoid clipping the last row separators/padding.
    private let pagesListExtraHeight: CGFloat = 8

    // Section 2.1.0 Document identity
    @State private var currentDocumentID: UUID? = nil

    // Section 2.1.1 Save Draft UI state
    @State private var isShowingSaveDraftAlert: Bool = false
    @State private var saveDraftAlertTitle: String = ""
    @State private var saveDraftAlertMessage: String = ""

    // Section 2.2 Environment
    @Environment(\.editMode) private var editMode

    // Section 2.2.1 Types (Entity Detection)
    private enum DetectedEntityKind: String {
        case url
        case email
        case phone
    }

    private struct DetectedEntity: Identifiable, Hashable {
        let id: UUID = UUID()
        let kind: DetectedEntityKind
        let value: String

        var displayTitle: String {
            switch kind {
            case .url: return value
            case .email: return value
            case .phone: return value
            }
        }

        var openURL: URL? {
            switch kind {
            case .url:
                // Ensure scheme for bare domains if needed.
                if let url = URL(string: value), url.scheme != nil { return url }
                if let url = URL(string: "https://\(value)") { return url }
                return nil
            case .email:
                return URL(string: "mailto:\(value)")
            case .phone:
                let digits = value.filter { "0123456789+*#,".contains($0) }
                return URL(string: "tel:\(digits)")
            }
        }
    }

    // Section 2.3 Init
    init(pages: [ScannerKit.ScannedPage], documentID: UUID? = nil) {
        _pages = State(initialValue: pages)
        _currentDocumentID = State(initialValue: documentID)
    }

    // Section 2.4 Body (intentionally thin to avoid Swift type-check blowups)
    var body: some View {
        ScrollView {
            content
                .padding(Theme.Spacing.lg)
        }
        .scannerScreen()
        .navigationTitle("Review")
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomControlPanel }
        .fullScreenCover(isPresented: isViewerPresented) { viewerCover }
        .sheet(isPresented: $isPresentingCamera) { cameraSheet }
        .alert(saveDraftAlertTitle, isPresented: $isShowingSaveDraftAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveDraftAlertMessage)
        }
        .confirmationDialog("Detected Items", isPresented: $isShowingEntityActions, titleVisibility: .visible) {
            ForEach(detectedEntities) { entity in
                Button(entity.displayTitle) {
                    openDetectedEntity(entity)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Tap an item to open it.")
        }
        .onAppear {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("ReviewView appeared with \(pages.count) pages") }
        }
        .onDisappear {
            persistEditsIfNeeded()
        }
    }

    // Section 2.5 Content
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            headerCard
            pagesCard
            Spacer(minLength: Theme.Spacing.xl)
        }
    }

    // Section 2.5.1 Header card
    private var headerCard: some View {
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
    }

    // Section 2.5.2 Pages card
    private var pagesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Captured Pages")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

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
                pagesList
            }
        }
        .scannerGlassCard(padding: Theme.Spacing.lg)
    }

    // Section 2.5.2.1 Pages list
    private var pagesListTargetHeight: CGFloat {
        let clampedCount = min(max(pages.count, pagesListVisibleRowsMin), pagesListVisibleRowsMax)
        return CGFloat(clampedCount) * pagesListRowHeight + pagesListExtraHeight
    }

    private var pagesList: some View {
        List {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                ReviewPageRow(
                    page: page,
                    refreshToken: viewerRefreshToken,
                    isEditing: editMode?.wrappedValue.isEditing == true,
                    onRotateClockwise: { rotate(pageID: page.id, clockwise: true) },
                    onRotateCounterClockwise: { rotate(pageID: page.id, clockwise: false) },
                    onTap: { selectedPageIndex = index }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove(perform: movePages)
            .onDelete(perform: deletePages)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Clamp container height to show 1–4 rows. List scrolls when pages > 4.
        .frame(height: pagesListTargetHeight)
        .scrollDisabled(pages.count <= pagesListVisibleRowsMax)
        .environment(\.defaultMinListRowHeight, pagesListRowHeight)
    }

    // Section 2.6 Viewer presentation binding
    private var isViewerPresented: Binding<Bool> {
        Binding(
            get: { selectedPageIndex != nil },
            set: { isPresented in
                if !isPresented { selectedPageIndex = nil }
            }
        )
    }

    // Section 2.7 Viewer cover
    @ViewBuilder
    private var viewerCover: some View {
        if let startIndex = selectedPageIndex {
            NavigationStack {
                ViewerView(
                    pages: $pages,
                    title: "Review",
                    initialIndex: startIndex,
                    refreshToken: viewerRefreshToken,
                    onRotatePage: { index, direction in
                        let clockwise = (direction == .right)
                        guard pages.indices.contains(index) else { return }
                        rotate(pageID: pages[index].id, clockwise: clockwise)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { selectedPageIndex = nil }
                    }
                }
            }
        }
    }

    // Section 2.8 Camera sheet
    private var cameraSheet: some View {
        DocumentCamera(presetRawValue: scanPresetRaw) { result in
            switch result {
            case .success(let newPages):
                let startIndex = pages.count
                let appended: [ScannerKit.ScannedPage] = newPages.enumerated().map { offset, page in
                    ScannerKit.ScannedPage(id: page.id, pageIndex: startIndex + offset, image: page.image, createdAt: page.createdAt)
                }
                pages.append(contentsOf: appended)
                hasUnsavedEdits = true
                viewerRefreshToken &+= 1

                if ScannerDebug.isEnabled {
                    ScannerDebug.writeLog("[ReviewView] Added \(appended.count) page(s). total=\(pages.count) viewerRefreshToken=\(viewerRefreshToken)")
                }

            case .cancelled:
                if ScannerDebug.isEnabled { ScannerDebug.writeLog("[ReviewView] Add Pages cancelled") }

            case .failure(let error):
                saveDraftAlertTitle = "Scan Failed"
                saveDraftAlertMessage = error.localizedDescription
                isShowingSaveDraftAlert = true
                if ScannerDebug.isEnabled { ScannerDebug.writeLog("[ReviewView] Add Pages failed: \(error.localizedDescription)") }
            }
        }
        .ignoresSafeArea()
    }

    // Section 3.6 Bottom Control Panel
    // Sits above the app's TabBar (Library / Scan / Settings) via safeAreaInset.
    private var bottomControlPanel: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Theme.Spacing.md) {

                Button { saveDraft() } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .imageScale(.large)
                }
                .disabled(pages.isEmpty)
                .accessibilityLabel("Save")

                Spacer()

                Button { exportPDFAndShare() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .imageScale(.large)
                }
                .disabled(pages.isEmpty)
                .accessibilityLabel("Share")

                Spacer()

                Menu {
                    Button {
                        Task { await recognizeText() }
                    } label: {
                        Label(isRecognizingText ? "Recognizing…" : "Recognize Text", systemImage: "text.viewfinder")
                    }
                    .disabled(pages.isEmpty || isRecognizingText)

                    Button {
                        copyRecognizedTextToClipboard()
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .disabled(pages.isEmpty)

                    Button {
                        presentDetectedEntityActions()
                    } label: {
                        Label("Actions", systemImage: "link")
                    }
                    .disabled(pages.isEmpty)

                } label: {
                    Image(systemName: "text.magnifyingglass")
                        .imageScale(.large)
                }
                .disabled(pages.isEmpty)
                .accessibilityLabel("Text")

                Spacer()

                Button {
                    isPresentingCamera = true
                    if ScannerDebug.isEnabled { ScannerDebug.writeLog("[ReviewView] Add Pages tapped (preset=\(scanPresetRaw))") }
                } label: {
                    Image(systemName: "plus.viewfinder")
                        .imageScale(.large)
                }
                .accessibilityLabel("Add Pages")

                Spacer()

                Button {
                    withAnimation {
                        if editMode?.wrappedValue.isEditing == true {
                            editMode?.wrappedValue = .inactive
                        } else {
                            editMode?.wrappedValue = .active
                        }
                    }
                } label: {
                    Text(editMode?.wrappedValue.isEditing == true ? "Done" : "Edit")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Edit")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.ultraThinMaterial)
        }
    }


    // Section 4. Actions
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

            let result = try ScannerDraftPersistence.saveDraft(documentID: currentDocumentID, pages: pages)
            currentDocumentID = result.documentID

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] saveDraft ok. documentID=\(result.documentID.uuidString) pages=\(result.pageCount)")
            }

            let preferredName = ScannerDraftPersistence.documentTitle(
                documentID: result.documentID,
                fileManager: fileManager
            ) ?? "Scan"

            let pdfURL = try ScannerDraftPersistence.pdfURLForSharing(
                documentID: result.documentID,
                preferredFilename: preferredName,
                fileManager: fileManager
            )

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

    // Section 4.0.1 OCR
    @MainActor
    private func recognizeText() async {
        guard !pages.isEmpty else { return }
        guard !isRecognizingText else { return }

        isRecognizingText = true
        defer { isRecognizingText = false }

        do {
            // Ensure we have a stable document identity so OCR can be persisted.
            let result = try ScannerDraftPersistence.saveDraft(documentID: currentDocumentID, pages: pages)
            currentDocumentID = result.documentID

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView][OCR] Starting OCR. documentID=\(result.documentID.uuidString) pages=\(pages.count)")
            }

            let ocr = try await ScannerOCRService.recognizeText(pages: pages)
            lastRecognizedText = ocr.fullText

            _ = try ScannerDraftPersistence.saveOCRResult(
                documentID: result.documentID,
                fullText: ocr.fullText,
                perPageText: ocr.perPageText
            )

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView][OCR] OCR complete. chars=\(ocr.fullText.count)")
            }

            saveDraftAlertTitle = "Text Recognized"
            saveDraftAlertMessage = "Recognized \(ocr.fullText.count) characters across \(pages.count) page(s).\n\nUse Text → Copy Text to copy to the clipboard."
            isShowingSaveDraftAlert = true

        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView][OCR] OCR failed: \(error.localizedDescription)")
            }
            saveDraftAlertTitle = "OCR Failed"
            saveDraftAlertMessage = error.localizedDescription
            isShowingSaveDraftAlert = true
        }
    }

    private func copyRecognizedTextToClipboard() {
        var textToCopy: String? = nil

        let trimmed = lastRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            textToCopy = trimmed
        } else if let docID = currentDocumentID {
            textToCopy = ScannerDraftPersistence.ocrFullTextIfAvailable(documentID: docID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let finalText = textToCopy, !finalText.isEmpty else {
            saveDraftAlertTitle = "No OCR Text"
            saveDraftAlertMessage = "Run Text → Recognize Text first."
            isShowingSaveDraftAlert = true
            return
        }

        UIPasteboard.general.string = finalText

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("[ReviewView][OCR] Copied OCR text to clipboard. chars=\(finalText.count)")
        }

        saveDraftAlertTitle = "Copied"
        saveDraftAlertMessage = "Copied \(finalText.count) characters to the clipboard."
        isShowingSaveDraftAlert = true
    }


    // Section 4.0.2 Entity Detection (URLs / emails / phones)
    private func presentDetectedEntityActions() {
        // Prefer in-memory OCR from the most recent recognize run; fall back to persisted OCR.
        var sourceText: String? = nil

        let trimmed = lastRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sourceText = trimmed
        } else if let docID = currentDocumentID {
            sourceText = ScannerDraftPersistence.ocrFullTextIfAvailable(documentID: docID)
        }

        guard let text = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            saveDraftAlertTitle = "No OCR Text"
            saveDraftAlertMessage = "Run Text → Recognize Text first."
            isShowingSaveDraftAlert = true
            return
        }

        let entities = detectEntities(in: text)
        guard !entities.isEmpty else {
            saveDraftAlertTitle = "No Items Found"
            saveDraftAlertMessage = "No links, emails, or phone numbers were detected."
            isShowingSaveDraftAlert = true
            return
        }

        detectedEntities = entities
        isShowingEntityActions = true

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("[ReviewView][OCR] Detected entities count=\(entities.count)")
        }
    }

    private func detectEntities(in text: String) -> [DetectedEntity] {
        var results: [DetectedEntity] = []

        // Detect URLs + phone numbers with NSDataDetector
        do {
            let types = NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            let detector = try NSDataDetector(types: types)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)

            detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match else { return }

                if match.resultType == .link, let url = match.url {
                    results.append(DetectedEntity(kind: .url, value: url.absoluteString))
                } else if match.resultType == .phoneNumber, let phone = match.phoneNumber {
                    results.append(DetectedEntity(kind: .phone, value: phone))
                }
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView][OCR] NSDataDetector init failed: \(error.localizedDescription)")
            }
        }

        // Detect emails with regex (NSDataDetector doesn't reliably cover email)
        let emailPattern = #"(?i)([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2,
                      let r = Range(match.range(at: 1), in: text) else { return }
                results.append(DetectedEntity(kind: .email, value: String(text[r])))
            }
        }

        // Deduplicate while preserving order; cap to 15 items.
        var seen = Set<DetectedEntity>()
        var deduped: [DetectedEntity] = []
        for item in results {
            if !seen.contains(item) {
                seen.insert(item)
                deduped.append(item)
            }
            if deduped.count >= 15 { break }
        }

        return deduped
    }

    private func openDetectedEntity(_ entity: DetectedEntity) {
        guard let url = entity.openURL else {
            saveDraftAlertTitle = "Can't Open"
            saveDraftAlertMessage = "Invalid item: \(entity.value)"
            isShowingSaveDraftAlert = true
            return
        }

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("[ReviewView][OCR] Opening entity kind=\(entity.kind.rawValue) url=\(url.absoluteString)")
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func rotate(pageID: UUID, clockwise: Bool) {
        guard let idx = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[idx] = pages[idx].rotated90(clockwise: clockwise)
        hasUnsavedEdits = true

        viewerRefreshToken &+= 1

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Rotated page id=\(pageID) clockwise=\(clockwise) viewerRefreshToken=\(viewerRefreshToken)")
        }
    }

    private func deletePages(at offsets: IndexSet) {
        pages.remove(atOffsets: offsets)
        pages = ScannerKit.ScannedPage.reindexed(pages)
        hasUnsavedEdits = true
        viewerRefreshToken &+= 1

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Deleted pages at offsets=\(Array(offsets)) -> remaining=\(pages.count) viewerRefreshToken=\(viewerRefreshToken)")
        }
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        pages = ScannerKit.ScannedPage.reindexed(pages)
        hasUnsavedEdits = true
        viewerRefreshToken &+= 1

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("Moved pages from=\(Array(source)) to=\(destination) viewerRefreshToken=\(viewerRefreshToken)")
        }
    }


    // Section 4.1 Persist edits (so Library thumbnails reflect rotations/reorders/deletes)
    private func persistEditsIfNeeded() {
        guard hasUnsavedEdits else { return }

        // Only persist if we already have an identity (i.e., came from Library or has been saved at least once).
        // If there is no documentID yet, we avoid implicitly creating one on dismiss; user can tap Save Draft.
        guard let docID = currentDocumentID else {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] persistEditsIfNeeded skipped (no documentID). hasUnsavedEdits=true")
            }
            return
        }

        // Ensure thumbnail regenerates so Library reflects edits immediately.
        // (Some persistence flows only create thumbnail if missing.)
        do {
            let paths = ScannerDocumentPaths(documentID: docID)
            let thumbURL = try paths.thumbnailURL()
            if FileManager.default.fileExists(atPath: thumbURL.path) {
                try FileManager.default.removeItem(at: thumbURL)
                if ScannerDebug.isEnabled { ScannerDebug.writeLog("[ReviewView] Deleted thumbnail before persist: \(thumbURL.lastPathComponent)") }
            }
        } catch {
            if ScannerDebug.isEnabled { ScannerDebug.writeLog("[ReviewView] WARNING: Could not delete thumbnail before persist: \(error.localizedDescription)") }
        }

        do {
            let result = try ScannerDraftPersistence.saveDraft(documentID: docID, pages: pages)
            currentDocumentID = result.documentID
            hasUnsavedEdits = false

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] persistEditsIfNeeded ok documentID=\(result.documentID.uuidString) pages=\(result.pageCount)")
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("[ReviewView] persistEditsIfNeeded FAILED documentID=\(docID.uuidString): \(error.localizedDescription)")
            }
            // Keep hasUnsavedEdits=true so a future attempt (e.g., user taps Save Draft) can persist.
        }
    }

    // Section 4.2 Share Presentation (UIKit)
    private func presentShareSheet(url: URL, documentID: UUID) {
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
        topVC.present(activityVC, animated: true)
    }
}

// Section 5. Row
private struct ReviewPageRow: View {

    // Section 5.1 Inputs
    let page: ScannerKit.ScannedPage
    let refreshToken: Int
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
                // Force refresh when the underlying UIImage changes (rotation, etc.).
                .id("\(page.id.uuidString)-\(refreshToken)")

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

// Section 6.1 Top-most view controller resolver (UIKit)
private enum ReviewViewTopMostViewControllerResolver {

    static func topMostViewController() -> UIViewController? {
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
    NavigationStack { ReviewView(pages: []) }
}

// End of file: ReviewView.swift

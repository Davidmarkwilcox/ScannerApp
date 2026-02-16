// LibraryView.swift
// File: LibraryView.swift
// Description:
// Library screen for ScannerApp.
// - Lists locally persisted scanner documents (draft + savedLocal states).
// - Provides row actions: open/view, rename, delete, Share PDF, and Share Images.
// - Share PDF will generate output/document.pdf on-demand (via ScannerKit) if missing.
// - Share Images shares the persisted page JPEGs (pages/001.jpg, 002.jpg, ...).
// - Rename defaults with the current name pre-selected for quick overwrite.
//
// Interactions:
// - Uses ScannerKit.ScannerDocumentStore for listing/rename/delete.
// - Uses ScannerKit.ScannerDraftPersistence.pdfURLForSharing(documentID:) to obtain/generate a PDF URL.
// - Uses ScannerKit.ScannerDraftPersistence.pageImageURLsForSharing(documentID:) to obtain page image URLs.
// - Uses ScannerKit.ScannerDocumentLoader to load pages when resuming ReviewView.
//
// Section 1. Imports
import SwiftUI
import UIKit
import ScannerKit

// Section 2. View
struct LibraryView: View {

    // Section 2.1 State
    @State private var documents: [ScannerDocumentMetadata] = []

    // Section 2.1.0 Thumbnail refresh token (forces thumbnail views to reload file-based images)
    @State private var thumbnailRefreshToken: Int = 0

    // Section 2.2 Rename UI
    @State private var renameTarget: ScannerDocumentMetadata? = nil

    // Section 2.3 Delete UI
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var deleteTarget: ScannerDocumentMetadata? = nil

    // Section 2.4 Share UI
    @State private var isShowingShareSheet: Bool = false
    @State private var shareItems: [Any] = []
    @State private var shareErrorMessage: String = ""
    @State private var isShowingShareError: Bool = false

    // Section 2.5 Body
    var body: some View {
        NavigationStack {
            List {
                // Section 2.5.1 Empty state
                if documents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No documents yet")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Scan a document, then tap Save Draft to persist it locally.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    // Section 2.5.2 Documents
                    ForEach(documents) { doc in
                        NavigationLink {
                            DocumentReviewRouteView(metadata: doc)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                LibraryThumbnailView(documentID: doc.documentID, refreshToken: thumbnailRefreshToken)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(doc.title)
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Text("\(doc.pageCount) page(s) • \(doc.state.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)

                                    Text(doc.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        // Section 2.5.2.1 Swipe actions
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                requestSharePDF(doc)
                            } label: {
                                Label("Share PDF", systemImage: "square.and.arrow.up")
                            }
                            .tint(Theme.Colors.accent)

                            Button {
                                requestShareImages(doc)
                            } label: {
                                Label("Share Images", systemImage: "photo.on.rectangle")
                            }
                            .tint(Theme.Colors.metallicGrey2)

                            Button {
                                requestRename(doc)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.Colors.metallicGrey2)

                            Button(role: .destructive) {
                                requestDelete(doc)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Section 2.5.2.2 Context menu (hard press)
                        .contextMenu {
                            Button {
                                requestSharePDF(doc)
                            } label: {
                                Label("Share PDF", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                requestShareImages(doc)
                            } label: {
                                Label("Share Images", systemImage: "photo.on.rectangle")
                            }

                            Button {
                                requestRename(doc)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                requestDelete(doc)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                // Section 2.6 Toolbar
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        reloadDocuments()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(Theme.Colors.textPrimary)
                }
            }
            .onAppear {
                reloadDocuments()
            }
            // Section 2.7 Delete confirmation (centered alert)
            .alert(
                "Delete Document?",
                isPresented: $isShowingDeleteConfirm,
                presenting: deleteTarget
            ) { _ in
                Button("Delete", role: .destructive) {
                    performDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: { doc in
                Text("This will permanently delete “\(doc.title)” from this device.")
            }
            // Section 2.8 Rename sheet
            .sheet(item: $renameTarget) { doc in
                RenameDocumentSheet(
                    initialTitle: doc.title,
                    onSave: { newTitle in
                        performRename(documentID: doc.documentID, newTitle: newTitle)
                    },
                    onCancel: {
                        renameTarget = nil
                    }
                )
            }
            // Section 2.9 Share sheet
            .sheet(isPresented: $isShowingShareSheet) {
                if !shareItems.isEmpty {
                    ShareSheet(activityItems: shareItems)
                } else {
                    Text("Nothing to share")
                        .onAppear { isShowingShareSheet = false }
                }
            }
            // Section 2.10 Share error
            .alert("Unable to Share", isPresented: $isShowingShareError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(shareErrorMessage)
            }
        }
    }

    // Section 3. Actions

    // Section 3.1 Reload
    private func reloadDocuments() {
        documents = ScannerDocumentStore.listDocuments()
        thumbnailRefreshToken &+= 1
        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("LibraryView reloadDocuments count=\(documents.count) thumbToken=\(thumbnailRefreshToken)")
        }
    }

    // Section 3.2 Share PDF
    private func requestSharePDF(_ doc: ScannerDocumentMetadata) {
        do {
            let url = try ScannerDraftPersistence.pdfURLForSharing(documentID: doc.documentID, preferredFilename: doc.title)
            shareItems = [url]
            isShowingShareSheet = true
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Share PDF documentID=\(doc.documentID.uuidString) url=\(url.path)")
            }
        } catch {
            shareErrorMessage = error.localizedDescription
            isShowingShareError = true
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Share PDF failed documentID=\(doc.documentID.uuidString): \(error.localizedDescription)")
            }
        }
    }

    // Section 3.3 Share Images
    private func requestShareImages(_ doc: ScannerDocumentMetadata) {
        do {
            let urls = try ScannerDraftPersistence.pageImageURLsForSharing(documentID: doc.documentID)
            shareItems = urls
            isShowingShareSheet = true
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Share Images documentID=\(doc.documentID.uuidString) count=\(urls.count)")
            }
        } catch {
            shareErrorMessage = error.localizedDescription
            isShowingShareError = true
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Share Images failed documentID=\(doc.documentID.uuidString): \(error.localizedDescription)")
            }
        }
    }

    // Section 3.4 Rename
    private func requestRename(_ doc: ScannerDocumentMetadata) {
        renameTarget = doc
        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("LibraryView requestRename documentID=\(doc.documentID.uuidString) title=\(doc.title)")
        }
    }

    private func performRename(documentID: UUID, newTitle: String) {
        do {
            let updated = try ScannerDocumentStore.renameDocument(documentID: documentID, newTitle: newTitle)
            if let idx = documents.firstIndex(where: { $0.documentID == updated.documentID }) {
                documents[idx] = updated
            } else {
                reloadDocuments()
            }
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Renamed documentID=\(updated.documentID.uuidString) title=\(updated.title)")
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Rename failed documentID=\(documentID.uuidString): \(error.localizedDescription)")
            }
            reloadDocuments()
        }
        renameTarget = nil
    }

// Section 3.5 Delete
    private func requestDelete(_ doc: ScannerDocumentMetadata) {
        deleteTarget = doc
        isShowingDeleteConfirm = true
    }

    private func performDelete() {
        guard let target = deleteTarget else { return }
        do {
            try ScannerDocumentStore.deleteDocument(documentID: target.documentID)
            documents.removeAll { $0.documentID == target.documentID }
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Deleted documentID=\(target.documentID.uuidString)")
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("LibraryView Delete failed documentID=\(target.documentID.uuidString): \(error.localizedDescription)")
            }
            reloadDocuments()
        }
        isShowingDeleteConfirm = false
        deleteTarget = nil
    }
}

// Section 4. Share Sheet (UIKit bridge)
private struct ShareSheet: UIViewControllerRepresentable {

    // Section 4.1 Inputs
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    // Section 4.2 Make
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    // Section 4.3 Update
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// Section 5. Rename Sheet
private struct RenameDocumentSheet: View {

    // Section 5.1 Inputs
    let initialTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    // Section 5.2 State
    @State private var text: String
    @State private var shouldFocusTitleField: Bool = false
    // Section 5.3 Init
    init(initialTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialTitle = initialTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialTitle)
    }

    // Section 5.4 Body
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                // Section 5.4.1 Title field (auto-select all on focus)
                SelectAllTextField("Title", text: $text, isFirstResponder: $shouldFocusTitleField)
                    .frame(height: 44)

                Spacer()
            }
            .padding()
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Ensure the TextField always starts with the current title.
                // (SwiftUI can reuse sheet views; resetting here avoids stale/empty text on first presentation.)
                text = initialTitle
                shouldFocusTitleField = false

                // Defer focus by a tick so UIKit has the updated text before selecting.
                DispatchQueue.main.async {
                    shouldFocusTitleField = true
                }

                if ScannerDebug.isEnabled {
                    ScannerDebug.writeLog("RenameDocumentSheet onAppear initialTitle=\(initialTitle)")
                }
            }
        }
    }
}

// Section 6. Select-all TextField (UIKit-backed)
//
// SwiftUI does not provide a reliable, public API to select all text in a TextField on appear.
// This wrapper uses UITextField and calls selectAll when it becomes first responder.
private struct SelectAllTextField: UIViewRepresentable {

    // Section 6.1 Inputs
    let placeholder: String
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    // Section 6.2 Init
    init(_ placeholder: String, text: Binding<String>, isFirstResponder: Binding<Bool>) {
        self.placeholder = placeholder
        self._text = text
        self._isFirstResponder = isFirstResponder
    }

    // Section 6.3 Coordinator
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        var didSelectAllOnce: Bool = false

        init(parent: SelectAllTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Keep SwiftUI state in sync for dictation / selection changes.
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Select all the first time we become first responder for this presentation.
            guard !didSelectAllOnce else { return }
            didSelectAllOnce = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("SelectAllTextField didBeginEditing -> selectAll")
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // Section 6.4 Make
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.placeholder = placeholder
        tf.text = text
        tf.borderStyle = .roundedRect
        tf.autocorrectionType = .default
        tf.autocapitalizationType = .sentences
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .done
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    // Section 6.5 Update
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        // Drive first responder from SwiftUI state.
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()

            // Ensure selection happens even if didBeginEditing fires before text is set.
            DispatchQueue.main.async {
                uiView.selectAll(nil)
            }

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("SelectAllTextField becomeFirstResponder -> selectAll")
            }
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("SelectAllTextField resignFirstResponder")
            }
        }
    }
}

// Section 7. Thumbnail
private struct LibraryThumbnailView: View {

    // Section 7.1 Input
    let documentID: UUID
    let refreshToken: Int

    // Section 7.2 Body
    var body: some View {
        Group {
            if let image = loadThumbnail(refreshToken: refreshToken) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.metallicGrey2.opacity(0.6))
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.Colors.glassStroke, lineWidth: 1)
        )
        // Force SwiftUI to recreate the thumbnail view when the token changes.
        .id("\(documentID.uuidString)-\(refreshToken)")
    }

    // Section 7.3 Loading
    private func loadThumbnail(refreshToken: Int) -> UIImage? {
        // Avoid potential image caching by loading bytes -> UIImage(data:).
        // refreshToken is intentionally unused except to influence view identity.
        do {
            let paths = ScannerDocumentPaths(documentID: documentID)
            let url = try paths.thumbnailURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

// Section 8. Viewer Route
private struct DocumentReviewRouteView: View {

    // Section 8.1 Input
    let metadata: ScannerDocumentMetadata

    // Section 8.2 State
    @State private var pages: [ScannerKit.ScannedPage] = []
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = true

    // Section 8.3 Body
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scannerScreen()
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Couldn’t load document")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(errorMessage)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Spacer()
                }
                .padding()
                .scannerScreen()
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ReviewView(pages: pages, documentID: metadata.documentID)
            }
        }
        .onAppear {
            load()
        }
    }

    // Section 8.4 Loading
    private func load() {
        guard isLoading else { return }
        do {
            pages = try ScannerDocumentLoader.loadPages(documentID: metadata.documentID)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// End of file: LibraryView.swift

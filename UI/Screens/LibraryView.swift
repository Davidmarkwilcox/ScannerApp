// LibraryView.swift
// File: LibraryView.swift
// Description: Placeholder Library screen. Eventually lists documents with thumbnails, unsaved indicators,
// and actions (open/view/share/save/delete). Styled with Theme defaults.
//
// Section 1. Imports
import SwiftUI
import ScannerKit

// Section 2. View
struct LibraryView: View {

    // Section 2.1 State
    @State private var documents: [ScannerDocumentMetadata] = []

    // Rename UI
    @State private var isShowingRenameSheet: Bool = false
    @State private var renameText: String = ""
    @State private var renameTarget: ScannerDocumentMetadata? = nil

    // Delete UI
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var deleteTarget: ScannerDocumentMetadata? = nil

    // Section 2.2 Body
    var body: some View {
        NavigationStack {
            List {
                // Section 2.2.1 Empty state
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
                    // Section 2.2.2 Documents
                    ForEach(documents) { doc in
                        NavigationLink {
                            DocumentViewerRouteView(metadata: doc)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                LibraryThumbnailView(documentID: doc.documentID)

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // Section 2.2.2.1 Delete
                            Button(role: .destructive) {
                                requestDelete(doc)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            // Section 2.2.2.2 Rename
                            Button {
                                requestRename(doc)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.Colors.accent)
                        }
                        .contextMenu {
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
                // Section 2.3 Toolbar
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
            // Section 2.4 Delete confirmation
            .confirmationDialog(
                "Delete Document?",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    performDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let doc = deleteTarget {
                    Text("This will permanently delete “\(doc.title)” from this device.")
                }
            }
            // Section 2.5 Rename sheet
            .sheet(isPresented: $isShowingRenameSheet) {
                RenameDocumentSheet(
                    initialTitle: renameText,
                    onSave: { newTitle in
                        renameText = newTitle
                        performRename()
                    },
                    onCancel: {
                        isShowingRenameSheet = false
                        renameTarget = nil
                    }
                )
            }
        }
    }

    // Section 3. Actions
    private func reloadDocuments() {
        documents = ScannerDocumentStore.listDocuments()
        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("LibraryView reloadDocuments count=\(documents.count)")
        }
    }

    private func requestRename(_ doc: ScannerDocumentMetadata) {
        renameTarget = doc
        renameText = doc.title
        isShowingRenameSheet = true
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        do {
            let updated = try ScannerDocumentStore.renameDocument(documentID: target.documentID, newTitle: renameText)
            // Update in-place to avoid full reload (still fine to reload if preferred)
            if let idx = documents.firstIndex(where: { $0.documentID == updated.documentID }) {
                documents[idx] = updated
            } else {
                reloadDocuments()
            }
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("Renamed documentID=\(updated.documentID.uuidString) title=\(updated.title)")
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("Rename failed documentID=\(target.documentID.uuidString): \(error.localizedDescription)")
            }
            // Fallback: reload to keep UI consistent
            reloadDocuments()
        }
        isShowingRenameSheet = false
        renameTarget = nil
    }

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
                ScannerDebug.writeLog("Deleted documentID=\(target.documentID.uuidString)")
            }
        } catch {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("Delete failed documentID=\(target.documentID.uuidString): \(error.localizedDescription)")
            }
            reloadDocuments()
        }
        isShowingDeleteConfirm = false
        deleteTarget = nil
    }
}

// Section 3.6 Rename Sheet
private struct RenameDocumentSheet: View {

    // Section 3.6.1 Inputs
    let initialTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    // Section 3.6.2 State
    @State private var text: String
    @FocusState private var isFocused: Bool

    // Section 3.6.3 Init
    init(initialTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialTitle = initialTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialTitle)
    }

    // Section 3.6.4 Body
    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    SelectAllTextField(text: $text)
                        .focused($isFocused)
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .tint(Theme.Colors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text) }
                        .tint(Theme.Colors.accent)
                }
            }
            .onAppear {
                // Focus and select all text on present
                isFocused = true
            }
        }
        .scannerScreen()
    }
}

// Section 3.7 Select-all TextField (UIKit-backed for reliable selection)
private struct SelectAllTextField: UIViewRepresentable {

    // Section 3.7.1 Binding
    @Binding var text: String

    // Section 3.7.2 Make
    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.borderStyle = .none
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .done
        tf.autocapitalizationType = .sentences
        tf.autocorrectionType = .default
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return tf
    }

    // Section 3.7.3 Update
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        // Select all once when the view first appears.
        if !context.coordinator.didSelectAllOnce {
            context.coordinator.didSelectAllOnce = true
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                uiView.selectAll(nil)
            }
        }
    }

    // Section 3.7.4 Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {

        // Section 3.7.4.1 State
        @Binding var text: String
        var didSelectAllOnce: Bool = false

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}


// Section 4. Thumbnail
private struct LibraryThumbnailView: View {

    // Section 4.1 Input
    let documentID: UUID

    // Section 5.2 Body
    var body: some View {
        let image = loadThumbnail()
        return Group {
            if let image {
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
    }

    // Section 4.3 Loading
    private func loadThumbnail() -> UIImage? {
        do {
            let paths = ScannerDocumentPaths(documentID: documentID)
            let url = try paths.thumbnailURL()
            return UIImage(contentsOfFile: url.path)
        } catch {
            return nil
        }
    }
}

// Section 5. Viewer Route
private struct DocumentViewerRouteView: View {

    // Section 5.1 Input
    let metadata: ScannerDocumentMetadata

    // Section 5.2 State
    @State private var pages: [ScannerKit.ScannedPage] = []
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = true

    // Section 5.3 Body
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
                .navigationTitle("Viewer")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ViewerView(pages: pages, title: metadata.title)
            }
        }
        .onAppear {
            load()
        }
    }

    // Section 5.4 Loading
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

// Section 5. Detail Stub
private struct LibraryDocumentDetailStubView: View {

    // Section 5.1 Inputs
    let metadata: ScannerDocumentMetadata

    // Section 5.2 Body
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metadata.title)
                .font(.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Document ID: \(metadata.documentID.uuidString)")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("State: \(metadata.state.rawValue)")
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Pages: \(metadata.pageCount)")
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// End of file: LibraryView.swift

// ViewerView.swift
// File: ViewerView.swift
// Description:
// Basic multi-page viewer for a persisted scanned document.
// - Displays page images with swipe navigation.
// - Supports pinch-to-zoom per page (simple MagnificationGesture).
// - Optional: exposes rotate controls via a callback so callers can mutate their own page state.
// - IMPORTANT: `pages` is a Binding so mutations in the presenting view (e.g., Review) reflect immediately.
// - IMPORTANT: `refreshToken` can be bumped by the caller to force page view re-creation when UIImage updates
//   are not picked up due to SwiftUI view identity caching.
//
// Interactions:
// - Called from LibraryView when a user selects a document (read-only via `.constant` binding).
// - Called from ReviewView for full-screen viewing (mutable binding + rotate handler + refreshToken bump).
//
// Section 1. Imports
import SwiftUI
import ScannerKit
import UIKit

// Section 2. View
struct ViewerView: View {

    // Section 2.1 Inputs
    @Binding private var pages: [ScannerKit.ScannedPage]
    let title: String

    /// Optional starting page index (used by Review to open directly to the tapped page).
    let initialIndex: Int

    /// A monotonic token. When this changes, page views are re-created to ensure image updates render.
    /// (Used to work around occasional SwiftUI caching of Image(uiImage:).)
    let refreshToken: Int

    /// Optional rotation hook. If provided, ViewerView will show rotate controls in the toolbar.
    /// The caller is responsible for mutating state (and persistence) as needed.
    let onRotatePage: ((Int, RotationDirection) -> Void)?

    // Section 2.2 State
    @State private var selectedIndex: Int = 0

    // Section 2.3 Rotation Direction
    enum RotationDirection {
        case left
        case right
    }

    // Section 2.4 Init (Binding-backed)
    init(
        pages: Binding<[ScannerKit.ScannedPage]>,
        title: String,
        initialIndex: Int = 0,
        refreshToken: Int = 0,
        onRotatePage: ((Int, RotationDirection) -> Void)? = nil
    ) {
        self._pages = pages
        self.title = title
        self.initialIndex = initialIndex
        self.refreshToken = refreshToken
        self.onRotatePage = onRotatePage
    }

    // Section 2.5 Init (read-only convenience)
    init(
        pages: [ScannerKit.ScannedPage],
        title: String,
        initialIndex: Int = 0,
        refreshToken: Int = 0,
        onRotatePage: ((Int, RotationDirection) -> Void)? = nil
    ) {
        self._pages = .constant(pages)
        self.title = title
        self.initialIndex = initialIndex
        self.refreshToken = refreshToken
        self.onRotatePage = onRotatePage
    }

    // Section 2.6 Body
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {

            // Section 2.6.1 Pager
            TabView(selection: $selectedIndex) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ZoomableImageView(image: page.image)
                        // Force a re-create when refreshToken changes (e.g., rotation).
                        .id("\(page.id.uuidString)-\(refreshToken)")
                        .tag(index)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Section 2.6.2 Page indicator
            Text("Page \(selectedIndex + 1) of \(pages.count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.md)
        }
        .scannerScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Section 2.6.3 Rotate controls (optional)
            if onRotatePage != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        rotate(.left)
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .disabled(pages.isEmpty)

                    Button {
                        rotate(.right)
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .disabled(pages.isEmpty)
                }
            }
        }
        .onAppear {
            // Section 2.6.4 Apply initial index safely
            let safeIndex = max(0, min(initialIndex, max(0, pages.count - 1)))
            selectedIndex = safeIndex

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("ViewerView appeared pages=\(pages.count) initialIndex=\(initialIndex) appliedIndex=\(safeIndex) refreshToken=\(refreshToken)")
            }
        }
        .onChange(of: selectedIndex) { oldValue, newValue in
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("ViewerView selectedIndex changed \(oldValue) -> \(newValue)")
            }
        }
        .onChange(of: pages.count) { oldValue, newValue in
            // Keep selection valid if caller mutates page list.
            if pages.isEmpty {
                selectedIndex = 0
            } else if selectedIndex >= pages.count {
                selectedIndex = max(0, pages.count - 1)
            }

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("ViewerView pages.count changed \(oldValue) -> \(newValue) selectedIndex=\(selectedIndex)")
            }
        }
    }

    // Section 2.7 Helpers
    private func rotate(_ direction: RotationDirection) {
        guard !pages.isEmpty else { return }

        if ScannerDebug.isEnabled {
            let dir = (direction == .left) ? "left" : "right"
            ScannerDebug.writeLog("ViewerView rotate tapped dir=\(dir) selectedIndex=\(selectedIndex)")
        }

        onRotatePage?(selectedIndex, direction)
    }
}

// Section 3. Zoomable Image
private struct ZoomableImageView: View {

    // Section 3.1 Input
    let image: UIImage

    // Section 3.2 State
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // Section 3.3 Body
    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1.0), 6.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .animation(.easeInOut(duration: 0.12), value: scale)
            }
        }
        .scannerGlassCard(padding: 0)
    }
}

// Section 4. Preview
#Preview {
    NavigationStack {
        ViewerView(pages: [], title: "Viewer")
    }
}

// End of file: ViewerView.swift

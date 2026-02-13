// ViewerView.swift
// File: ViewerView.swift
// Description:
// Basic multi-page viewer for a persisted scanned document.
// - Displays page images with swipe navigation.
// - Supports pinch-to-zoom per page (simple MagnificationGesture).
// - v1: no PDF, no share/export yet.
//
// Interactions:
// - Called from LibraryView when a user selects a document.
// - Renders pages loaded from ScannerKit (ScannerDocumentLoader).
//
// Section 1. Imports
import SwiftUI
import ScannerKit
import UIKit

// Section 2. View
struct ViewerView: View {

    // Section 2.1 Inputs
    let pages: [ScannerKit.ScannedPage]
    let title: String

    // Section 2.2 State
    @State private var selectedIndex: Int = 0

    // Section 2.3 Init
    init(pages: [ScannerKit.ScannedPage], title: String) {
        self.pages = pages
        self.title = title
    }

    // Section 2.4 Body
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {

            // Section 2.4.1 Pager
            TabView(selection: $selectedIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    ZoomableImageView(image: page.image)
                        .tag(index)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Section 2.4.2 Page indicator
            Text("Page \(selectedIndex + 1) of \(pages.count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.bottom, Theme.Spacing.md)
        }
        .scannerScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("ViewerView appeared pages=\(pages.count)")
            }
        }
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

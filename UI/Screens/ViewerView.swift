// ViewerView.swift
// File: ViewerView.swift
// Description:
// Multi-page viewer for ScannerApp.
//
// Responsibilities:
// - Displays scanned pages in a horizontal pager.
// - Provides robust, deterministic pinch-to-zoom + pan per page via a UIKit-backed UIScrollView.
// - Provides PencilKit MarkUp overlay with explicit Save / Cancel semantics.
//    - Enter MarkUp: tool picker shows immediately.
//    - Save: bakes drawing into the underlying UIImage and writes back to `pages[selectedIndex]`.
//    - Cancel/Exit without Save: discards drawing and leaves the image unchanged.
//
// Interactions:
// - Used from LibraryView (read-only `.constant` pages) and ReviewView (mutable binding).
// - Optional `onRotatePage` hook allows ReviewView to implement rotation/persistence.
//
// Debugging:
// - Controlled by `ScannerDebug.isEnabled`.
// - Contains targeted zoom-fit logs to diagnose lifecycle/presentation issues.
//
// Section 1. Imports
import SwiftUI
import ScannerKit
import UIKit
import QuartzCore
import PencilKit

// MARK: - Section 2. ViewerView (SwiftUI)

struct ViewerView: View {

    // Section 2.1 Inputs
    @Binding private var pages: [ScannerKit.ScannedPage]
    let title: String
    let initialIndex: Int
    let refreshToken: Int
    let onRotatePage: ((Int, RotationDirection) -> Void)?

    // Section 2.2 State
    @State private var selectedIndex: Int = 0

    // Forces a deterministic “new presentation” signal to the UIKit view on each appearance.
    @State private var presentationID: UUID = UUID()

    // MarkUp
    @State private var isMarkupMode: Bool = false
    @State private var currentDrawing: PKDrawing = PKDrawing()
    @State private var markupIsDirty: Bool = false
    @State private var canUndo: Bool = false
    @State private var canRedo: Bool = false
    @State private var undoTick: Int = 0
    @State private var redoTick: Int = 0

    // Section 2.2.1 Viewport persistence (zoom + pan)
    fileprivate struct PageViewport: Equatable {
        // Content-space point (in the unscaled image coordinate system) that should remain centered
        // when toggling MarkUp. This is more stable than raw contentOffset, which is affected by
        // contentInset changes and centering logic.
        var zoomScale: CGFloat
        var contentCenter: CGPoint
    }

    @State private var viewportByPageID: [UUID: PageViewport] = [:]
    @State private var pendingRestoreForPageID: UUID? = nil
    @State private var restoreToken: UUID = UUID()

    // When entering MarkUp, we snapshot the current viewport and temporarily suppress viewport writes.
    // This prevents the newly-created MarkUp UIScrollView (which starts at zoomScale=1.0, offset=(0,0))
    // from overwriting the user's last viewport before restore happens.
    @State private var enteringMarkupViewport: PageViewport? = nil
    @State private var suppressViewportUpdatesForPageID: UUID? = nil

    // Section 2.3 Rotation Direction
    enum RotationDirection { case left, right }

    // Section 2.4 Init (binding-backed)
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
            // IMPORTANT: Do NOT disable the TabView tree during MarkUp.
            // SwiftUI's `.disabled(true)` prevents touch delivery to UIKit views, which makes PKCanvasView appear "not drawing".
            if isMarkupMode {
                // In MarkUp mode, render only the selected page (no paging gestures).
                if pages.indices.contains(selectedIndex) {
                    let page = pages[selectedIndex]
                    PencilMarkupZoomView(
                        image: page.image,
                        isMarkupMode: true,
                        drawing: Binding(
                            get: { currentDrawing },
                            set: { newValue in
                                currentDrawing = newValue
                                markupIsDirty = !newValue.strokes.isEmpty
                            }
                        ),
                        presentationID: presentationID,
                        undoTick: undoTick,
                        redoTick: redoTick,
                        initialViewport: enteringMarkupViewport ?? viewportByPageID[page.id],
                        restoreToken: (pendingRestoreForPageID == page.id) ? restoreToken : nil,
                        onDirtyChanged: { dirty in
                            markupIsDirty = dirty
                        },
                        onUndoRedoAvailabilityChanged: { newCanUndo, newCanRedo in
                            canUndo = newCanUndo
                            canRedo = newCanRedo
                        },
                        onViewportChanged: { zoom, offset in
                            if suppressViewportUpdatesForPageID == page.id { return }
                            viewportByPageID[page.id] = PageViewport(zoomScale: zoom, contentCenter: offset)
                        }
                    )
                    .id("\(page.id.uuidString)-\(refreshToken)-\(presentationID.uuidString)-markup")
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding([.top, .bottom], Theme.Spacing.sm)
                }
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        PencilMarkupZoomView(
                            image: page.image,
                            isMarkupMode: false,
                            drawing: Binding(
                                get: { currentDrawing },
                                set: { newValue in
                                    currentDrawing = newValue
                                    markupIsDirty = !newValue.strokes.isEmpty
                                }
                            ),
                            presentationID: presentationID,
                            undoTick: undoTick,
                            redoTick: redoTick,
                            initialViewport: viewportByPageID[page.id],
                            restoreToken: nil,
                            onDirtyChanged: { dirty in
                                markupIsDirty = dirty
                            },
                            onUndoRedoAvailabilityChanged: { _, _ in },
                            onViewportChanged: { zoom, offset in
                                if suppressViewportUpdatesForPageID == page.id { return }
                                viewportByPageID[page.id] = PageViewport(zoomScale: zoom, contentCenter: offset)
                            }
                        )
                        // Combine page identity, refreshToken, and presentationID so UIKit state does not leak across presentations.
                        .id("\(page.id.uuidString)-\(refreshToken)-\(presentationID.uuidString)")
                        .tag(index)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding([.top, .bottom], Theme.Spacing.sm)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

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
            // Section 2.6.3 Toolbar actions
            ToolbarItemGroup(placement: .topBarTrailing) {

                Button {
                    toggleMarkup()
                } label: {
                    Image(systemName: isMarkupMode ? "pencil.slash" : "pencil.tip")
                }
                .disabled(pages.isEmpty)

                if isMarkupMode {

                    Button {
                        undoTick += 1
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)

                    Button {
                        redoTick += 1
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)

                    Button {
                        saveMarkup()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!markupIsDirty)

                    Button(role: .cancel) {
                        cancelMarkup()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                if onRotatePage != nil {
                    Button { rotate(.left) } label: { Image(systemName: "rotate.left") }
                        .disabled(pages.isEmpty || isMarkupMode)

                    Button { rotate(.right) } label: { Image(systemName: "rotate.right") }
                        .disabled(pages.isEmpty || isMarkupMode)
                }
            }
        }
        .onAppear {
            // Section 2.6.4 New presentation token (forces fresh fit behavior)
            presentationID = UUID()

            // Section 2.6.5 Apply initial index safely
            let safeIndex = max(0, min(initialIndex, max(0, pages.count - 1)))
            selectedIndex = safeIndex

            if ScannerDebug.isEnabled {
                ScannerDebug.writeLog("ViewerView appeared pages=\(pages.count) initialIndex=\(initialIndex) appliedIndex=\(safeIndex) refreshToken=\(refreshToken) presentationID=\(presentationID.uuidString)")
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            if isMarkupMode { cancelMarkup() }
        }
        .onChange(of: pages.count) { _, _ in
            if pages.isEmpty {
                selectedIndex = 0
                cancelMarkup()
            } else if selectedIndex >= pages.count {
                selectedIndex = max(0, pages.count - 1)
            }
        }
    }

    // MARK: - Section 2.7 Helpers

    private func rotate(_ direction: RotationDirection) {
        guard !pages.isEmpty else { return }
        onRotatePage?(selectedIndex, direction)
    }

    private func toggleMarkup() {
        guard !pages.isEmpty else { return }

        if isMarkupMode {
            cancelMarkup()
            return
        }

        // Snapshot the current viewport (from non-MarkUp) and suppress writes while the MarkUp
        // UIScrollView is being created/restored. Without this, the new scroll view's default
        // (zoom=1.0, center=(0,0)) can overwrite `viewportByPageID` before restore runs.
        if pages.indices.contains(selectedIndex) {
            let pageID = pages[selectedIndex].id
            enteringMarkupViewport = viewportByPageID[pageID]
            suppressViewportUpdatesForPageID = pageID
        } else {
            enteringMarkupViewport = nil
            suppressViewportUpdatesForPageID = nil
        }

        currentDrawing = PKDrawing()
        markupIsDirty = false
        canUndo = false
        canRedo = false
        // Bump ticks so the representable has a stable baseline for comparisons.
        undoTick = 0
        redoTick = 0
        isMarkupMode = true

        // Preserve the user's current zoom/pan when entering MarkUp.
        if pages.indices.contains(selectedIndex) {
            pendingRestoreForPageID = pages[selectedIndex].id
            restoreToken = UUID()

            // Release suppression shortly after the restore has had a chance to apply.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                suppressViewportUpdatesForPageID = nil
                enteringMarkupViewport = nil
            }
        }

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("ViewerView MarkUp ON selectedIndex=\(selectedIndex)")
        }
    }

    private func cancelMarkup() {
        guard isMarkupMode else { return }
        isMarkupMode = false
        currentDrawing = PKDrawing()
        markupIsDirty = false
        canUndo = false
        canRedo = false
        pendingRestoreForPageID = nil
        enteringMarkupViewport = nil
        suppressViewportUpdatesForPageID = nil

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("ViewerView MarkUp CANCEL selectedIndex=\(selectedIndex)")
        }
    }

    private func saveMarkup() {
        guard isMarkupMode else { return }
        guard pages.indices.contains(selectedIndex) else { return }

        let page = pages[selectedIndex]

        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("ViewerView MarkUp SAVE selectedIndex=\(selectedIndex) dirty=\(markupIsDirty) strokes=\(currentDrawing.strokes.count)")
        }

        let baked = bake(drawing: currentDrawing, onto: page.image)

        pages[selectedIndex] = ScannerKit.ScannedPage(
            id: page.id,
            pageIndex: page.pageIndex,
            image: baked,
            createdAt: page.createdAt
        )

        isMarkupMode = false
        currentDrawing = PKDrawing()
        markupIsDirty = false
        canUndo = false
        canRedo = false
        pendingRestoreForPageID = nil
        enteringMarkupViewport = nil
        suppressViewportUpdatesForPageID = nil
    }

    private func bake(drawing: PKDrawing, onto image: UIImage) -> UIImage {
        if drawing.strokes.isEmpty { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let drawingImage = drawing.image(from: CGRect(origin: .zero, size: image.size), scale: image.scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - Section 3. PencilMarkupZoomView (UIViewRepresentable)

private struct PencilMarkupZoomView: UIViewRepresentable {

    // Section 3.1 Inputs
    let image: UIImage
    let isMarkupMode: Bool
    @Binding var drawing: PKDrawing
    let presentationID: UUID
    let undoTick: Int
    let redoTick: Int
    let initialViewport: ViewerView.PageViewport?
    let restoreToken: UUID?
    let onDirtyChanged: (Bool) -> Void
    let onUndoRedoAvailabilityChanged: (Bool, Bool) -> Void
    let onViewportChanged: (CGFloat, CGPoint) -> Void

    // Section 3.2 Coordinator
    final class Coordinator: NSObject, UIScrollViewDelegate, PKCanvasViewDelegate {

        private let debugEnabled: Bool

        weak var scrollView: FitScrollView?
        weak var contentView: UIView?
        weak var imageView: UIImageView?
        weak var canvasView: PKCanvasView?

        weak var toolPicker: PKToolPicker?

        private(set) var lastPresentationID: UUID?
        private(set) var lastContentSize: CGSize = .zero
        var pendingFit: Bool = true
        var userDidZoom: Bool = false
        private var pendingToolPickerVisible: Bool = false
        var lastUndoTick: Int = 0
        var lastRedoTick: Int = 0
        var isMarkupModeFlag: Bool = false
        var pendingRestoreViewport: ViewerView.PageViewport? = nil
        var pendingRestoreToken: UUID? = nil
        private var lastAppliedRestoreToken: UUID? = nil

        // Viewport publish throttling (prevents excessive SwiftUI state churn during scroll/zoom)
        private var lastPublishedZoom: CGFloat = -1
        private var lastPublishedCenter: CGPoint = CGPoint(x: -1, y: -1)
        private var lastViewportPublishTime: CFTimeInterval = 0

        var onDirtyChanged: ((Bool) -> Void)?
        var onDrawingChanged: ((PKDrawing) -> Void)?
        var onUndoRedoAvailabilityChanged: ((Bool, Bool) -> Void)?
        var onViewportChanged: ((CGFloat, CGPoint) -> Void)?

        init(debugEnabled: Bool) {
            self.debugEnabled = debugEnabled
            super.init()
        }

        // UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            userDidZoom = true
            if debugEnabled { ScannerDebug.writeLog("PencilMarkupZoomView willBeginZooming") }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent()
            publishViewportIfNeeded(scrollView: scrollView, reason: "didZoom")
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishViewportIfNeeded(scrollView: scrollView, reason: "didScroll")
        }

        fileprivate func computeContentCenter(scrollView: UIScrollView) -> CGPoint {
            // Translate the currently visible center into *content* coordinates.
            // IMPORTANT: Do NOT adjust for contentInset here.
            // When we center content using `contentInset`, UIScrollView expresses that as a
            // negative contentOffset. Using `contentOffset + bounds/2` correctly yields the
            // visible center in the scroll view's content coordinate space.
            let boundsSize = scrollView.bounds.size
            let visibleCenterX = scrollView.contentOffset.x + (boundsSize.width / 2)
            let visibleCenterY = scrollView.contentOffset.y + (boundsSize.height / 2)

            let z = max(scrollView.zoomScale, 0.0001)
            return CGPoint(x: visibleCenterX / z, y: visibleCenterY / z)
        }

        private func shouldPublishViewport(zoom: CGFloat, center: CGPoint) -> Bool {
            // Epsilon thresholds to avoid spamming minor float jitter.
            let zoomEps: CGFloat = 0.001
            let centerEps: CGFloat = 0.5 // content-space points

            if abs(zoom - lastPublishedZoom) > zoomEps { return true }
            if abs(center.x - lastPublishedCenter.x) > centerEps { return true }
            if abs(center.y - lastPublishedCenter.y) > centerEps { return true }
            return false
        }

        private func publishViewportIfNeeded(scrollView: UIScrollView, reason: String) {
            guard let onViewportChanged else { return }

            let zoom = scrollView.zoomScale
            let center = computeContentCenter(scrollView: scrollView)

            // Throttle: cap publish rate to ~30 Hz.
            let now = CACurrentMediaTime()
            let minInterval: CFTimeInterval = 1.0 / 30.0
            if now - lastViewportPublishTime < minInterval {
                // Still allow a publish if a meaningful jump happened.
                if !shouldPublishViewport(zoom: zoom, center: center) { return }
            }

            // Change detection
            if !shouldPublishViewport(zoom: zoom, center: center) { return }

            lastViewportPublishTime = now
            lastPublishedZoom = zoom
            lastPublishedCenter = center

            onViewportChanged(zoom, center)

            if debugEnabled {
                ScannerDebug.writeLog("PencilMarkupZoomView viewport published (\(reason)) zoom=\(zoom) center=\(center)")
            }
        }

        func restoreViewportIfNeeded(reason: String) {
            guard isMarkupModeFlag else { return }
            guard let scrollView else { return }
            guard let token = pendingRestoreToken else { return }
            guard lastAppliedRestoreToken != token else { return }
            guard let vp = pendingRestoreViewport else { return }

            // Only restore once we have real bounds.
            let boundsSize = scrollView.bounds.size
            if boundsSize.width <= 10 || boundsSize.height <= 10 { return }

            lastAppliedRestoreToken = token
            pendingFit = false
            userDidZoom = true

            scrollView.minimumZoomScale = min(scrollView.minimumZoomScale, vp.zoomScale)
            scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, vp.zoomScale)

            // 1) Apply zoom
            scrollView.setZoomScale(vp.zoomScale, animated: false)

            // 2) Re-center insets (affects valid offsets)
            centerContent()

            // 3) Compute an offset that keeps the same content point centered.
            let inset = scrollView.contentInset
            let bounds = scrollView.bounds.size
            let z = scrollView.zoomScale
            let desiredOffset = CGPoint(
                x: (vp.contentCenter.x * z) - (bounds.width / 2),
                y: (vp.contentCenter.y * z) - (bounds.height / 2)
            )

            // Clamp to valid scroll range (allows negative min due to insets).
            let contentSize = scrollView.contentSize
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, contentSize.width - bounds.width + inset.right)
            let maxY = max(minY, contentSize.height - bounds.height + inset.bottom)
            let clamped = CGPoint(
                x: min(max(desiredOffset.x, minX), maxX),
                y: min(max(desiredOffset.y, minY), maxY)
            )

            scrollView.setContentOffset(clamped, animated: false)

            if debugEnabled {
                ScannerDebug.writeLog("PencilMarkupZoomView RESTORE (\(reason)) zoom=\(vp.zoomScale) center=\(vp.contentCenter) offset=\(clamped)")
            }
        }

        // PKCanvasViewDelegate
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let isDirty = !canvasView.drawing.strokes.isEmpty
            onDirtyChanged?(isDirty)
            onDrawingChanged?(canvasView.drawing)
            if debugEnabled {
                ScannerDebug.writeLog("PencilMarkupZoomView drawingDidChange strokes=\(canvasView.drawing.strokes.count)")
            }
            publishUndoRedoAvailability()
        }

        private func publishUndoRedoAvailability() {
            guard let canvasView else { return }
            let um = canvasView.undoManager
            let canUndo = um?.canUndo ?? false
            let canRedo = um?.canRedo ?? false
            onUndoRedoAvailabilityChanged?(canUndo, canRedo)
        }

        // Presentation / content lifecycle
        func markNewPresentation(_ id: UUID) {
            if lastPresentationID != id {
                lastPresentationID = id
                userDidZoom = false
                pendingFit = true
                lastPublishedZoom = -1
                lastPublishedCenter = CGPoint(x: -1, y: -1)
                lastViewportPublishTime = 0
                if debugEnabled { ScannerDebug.writeLog("PencilMarkupZoomView new presentationID=\(id.uuidString) -> reset") }
            }
        }

        func setContentSizeIfNeeded(_ size: CGSize) {
            if lastContentSize != size {
                lastContentSize = size
                userDidZoom = false
                pendingFit = true
                if debugEnabled { ScannerDebug.writeLog("PencilMarkupZoomView contentSize changed -> \(size) -> reset") }
            }
        }

        func applyFitIfNeeded(reason: String) {
            guard let scrollView, let contentView else { return }

            let boundsSize = scrollView.bounds.size
            if boundsSize.width <= 10 || boundsSize.height <= 10 { return }

            let contentSize = contentView.bounds.size
            if contentSize.width <= 0 || contentSize.height <= 0 { return }

            let xScale = boundsSize.width / contentSize.width
            let yScale = boundsSize.height / contentSize.height
            let fitScale = min(xScale, yScale)
            let startScale: CGFloat = min(1.0, fitScale)

            // When MarkUp is active, do not re-fit; it would reset the user's zoom/pan.
            if isMarkupModeFlag {
                scrollView.minimumZoomScale = min(scrollView.minimumZoomScale, startScale)
                scrollView.maximumZoomScale = 6.0
                centerContent()
                return
            }

            scrollView.minimumZoomScale = startScale
            scrollView.maximumZoomScale = 6.0

            let shouldApply = pendingFit || !userDidZoom
            if shouldApply {
                pendingFit = false
                scrollView.setZoomScale(startScale, animated: false)

                if debugEnabled {
                    ScannerDebug.writeLog("""
                    ZOOM APPLY (\(reason))
                    boundsSize: \(boundsSize)
                    contentSize: \(contentSize)
                    xScale: \(xScale)
                    yScale: \(yScale)
                    fitScale: \(fitScale)
                    startScale: \(startScale)
                    zoomScaleNow: \(scrollView.zoomScale)
                    """)
                }
            }

            centerContent()
        }

        private func centerContent() {
            guard let scrollView, let contentView else { return }

            let contentFrame = contentView.frame
            let bounds = scrollView.bounds.size

            let horizontalInset = max(0, (bounds.width - contentFrame.size.width) / 2)
            let verticalInset = max(0, (bounds.height - contentFrame.size.height) / 2)

            let inset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            if scrollView.contentInset != inset {
                scrollView.contentInset = inset
            }
        }

        // Tool picker
        func setToolPickerVisible(_ visible: Bool) {
            guard let canvasView else { return }

            // Most common cause of "shows on 2nd tap": the canvas isn't in a window yet.
            // If so, defer and retry on the next layout pass.
            if toolPicker == nil {
                guard let window = canvasView.window ?? UIApplication.shared.scanner_keyWindow else {
                    if visible {
                        pendingToolPickerVisible = true
                    }
                    if debugEnabled {
                        ScannerDebug.writeLog("PencilMarkupZoomView toolPicker: no window yet (defer=\(visible))")
                    }
                    return
                }
                toolPicker = PKToolPicker.shared(for: window)
            }

            guard let toolPicker else { return }

            if visible {
                // Defensive, multi-pass show logic to cover responder-chain timing issues.
                // Order matters: first responder FIRST, then show picker.
                DispatchQueue.main.async {
                    // Pass 1
                    canvasView.isUserInteractionEnabled = true
                    canvasView.becomeFirstResponder()
                    toolPicker.addObserver(canvasView)
                    toolPicker.setVisible(true, forFirstResponder: canvasView)

                    if self.debugEnabled {
                        ScannerDebug.writeLog("PencilMarkupZoomView toolPicker visible=TRUE (1st pass) isFirstResponder=\(canvasView.isFirstResponder)")
                    }

                    // Pass 2 (next run loop) — some OS builds need this to reliably display on first toggle.
                    DispatchQueue.main.async {
                        toolPicker.addObserver(canvasView)
                        toolPicker.setVisible(true, forFirstResponder: canvasView)
                        canvasView.becomeFirstResponder()

                        if self.debugEnabled {
                            ScannerDebug.writeLog("PencilMarkupZoomView toolPicker visible=TRUE (2nd pass) isFirstResponder=\(canvasView.isFirstResponder)")
                        }
                    }
                }
            } else {
                pendingToolPickerVisible = false
                toolPicker.setVisible(false, forFirstResponder: canvasView)
                toolPicker.removeObserver(canvasView)

                if debugEnabled {
                    ScannerDebug.writeLog("PencilMarkupZoomView toolPicker visible=FALSE")
                }
            }
        }

        func retryPendingToolPickerIfNeeded() {
            guard pendingToolPickerVisible else { return }
            guard let canvasView else { return }
            // Only retry once the canvas can be associated to a window/tool picker.
            guard (canvasView.window ?? UIApplication.shared.scanner_keyWindow) != nil else { return }
            pendingToolPickerVisible = false
            setToolPickerVisible(true)
        }
    }

    // Make Coordinator
    func makeCoordinator() -> Coordinator {
        let c = Coordinator(debugEnabled: ScannerDebug.isEnabled)
        c.onDirtyChanged = { dirty in
            self.onDirtyChanged(dirty)
        }
        c.onUndoRedoAvailabilityChanged = { canUndo, canRedo in
            self.onUndoRedoAvailabilityChanged(canUndo, canRedo)
        }
        c.onViewportChanged = { zoom, offset in
            self.onViewportChanged(zoom, offset)
        }
        return c
    }

    // Make UIView
    func makeUIView(context: Context) -> FitScrollView {

        let scroll = FitScrollView()
        scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        // Make PencilKit touch handling friendlier inside a scroll view
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = false
        scroll.delegate = context.coordinator

        let content = UIView()
        content.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear

        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.allowsFingerDrawing = true
        canvas.isUserInteractionEnabled = false
        canvas.delegate = context.coordinator

        content.addSubview(imageView)
        content.addSubview(canvas)
        scroll.addSubview(content)

        context.coordinator.scrollView = scroll
        context.coordinator.contentView = content
        context.coordinator.imageView = imageView
        context.coordinator.canvasView = canvas

        scroll.fitHandler = { [weak coord = context.coordinator] in
            coord?.applyFitIfNeeded(reason: "layoutSubviews")
            // If MarkUp was toggled on before the canvas had a window, retry now.
            coord?.retryPendingToolPickerIfNeeded()
            coord?.restoreViewportIfNeeded(reason: "layoutSubviews")
        }

        return scroll
    }

    // Update UIView
    func updateUIView(_ uiView: FitScrollView, context: Context) {
        guard let content = context.coordinator.contentView,
              let imageView = context.coordinator.imageView,
              let canvas = context.coordinator.canvasView else { return }

        // Keep the SwiftUI binding in sync while the user draws. Without this, SwiftUI may repeatedly
        // reset the canvas back to the previous binding value (often empty), making ink appear invisible.
        context.coordinator.onDrawingChanged = { newDrawing in
            if self.drawing != newDrawing {
                self.drawing = newDrawing
            }
        }

        context.coordinator.markNewPresentation(presentationID)

        imageView.image = image

        let contentSize = image.size
        context.coordinator.setContentSizeIfNeeded(contentSize)

        // Layout only when needed (keeps zoomScale stable)
        if content.bounds.size != contentSize {
            content.frame = CGRect(origin: .zero, size: contentSize)
            imageView.frame = content.bounds
            canvas.frame = content.bounds
            uiView.contentSize = contentSize
        }

        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }

        canvas.isUserInteractionEnabled = isMarkupMode

        // Keep coordinator in sync so layoutSubviews won't re-fit when MarkUp is active.
        context.coordinator.isMarkupModeFlag = isMarkupMode
        context.coordinator.pendingRestoreViewport = initialViewport
        context.coordinator.pendingRestoreToken = restoreToken

        // MarkUp gesture policy:
        // - 1 finger draws on PKCanvasView
        // - 2 fingers pan/zoom the page (UIScrollView)
        if isMarkupMode {
            uiView.isScrollEnabled = true
            uiView.panGestureRecognizer.isEnabled = true
            uiView.panGestureRecognizer.minimumNumberOfTouches = 2
            uiView.pinchGestureRecognizer?.isEnabled = true
        } else {
            uiView.isScrollEnabled = true
            uiView.panGestureRecognizer.isEnabled = true
            uiView.panGestureRecognizer.minimumNumberOfTouches = 1
            uiView.pinchGestureRecognizer?.isEnabled = true
        }

        // Apply fit as a safety net; primary fit is layoutSubviews.
        if !isMarkupMode {
            context.coordinator.applyFitIfNeeded(reason: "updateUIView")
        }

        context.coordinator.setToolPickerVisible(isMarkupMode)

        // Attempt viewport restore during update cycle as well (covers cases where layout happens before fitHandler runs).
        context.coordinator.restoreViewportIfNeeded(reason: "updateUIView")

        // Publish current viewport snapshot.
        // NOTE: Intentionally skipped here to avoid SwiftUI state feedback loops during paging.
        if ScannerDebug.isEnabled {
            ScannerDebug.writeLog("PencilMarkupZoomView viewport publish skipped (updateUIView)")
        }

        if isMarkupMode {
            // Apply undo/redo commands triggered from SwiftUI toolbar.
            if context.coordinator.lastUndoTick != undoTick {
                context.coordinator.lastUndoTick = undoTick
                canvas.undoManager?.undo()
                if ScannerDebug.isEnabled {
                    ScannerDebug.writeLog("PencilMarkupZoomView UNDO")
                }
            }

            if context.coordinator.lastRedoTick != redoTick {
                context.coordinator.lastRedoTick = redoTick
                canvas.undoManager?.redo()
                if ScannerDebug.isEnabled {
                    ScannerDebug.writeLog("PencilMarkupZoomView REDO")
                }
            }

            // Update availability after commands.
            context.coordinator.onUndoRedoAvailabilityChanged?(canvas.undoManager?.canUndo ?? false, canvas.undoManager?.canRedo ?? false)
        } else {
            // Reset tick baselines when not in MarkUp.
            context.coordinator.lastUndoTick = undoTick
            context.coordinator.lastRedoTick = redoTick
        }
    }
}

// MARK: - Section 4. FitScrollView

private final class FitScrollView: UIScrollView {
    var fitHandler: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        fitHandler?()
    }
}

// MARK: - Section 5. UIApplication helpers

private extension UIApplication {
    var scanner_keyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return scenes.first?.windows.first
    }
}

// MARK: - Section 6. Preview

#Preview {
    NavigationStack {
        ViewerView(pages: [], title: "Viewer")
    }
}

// End of file: ViewerView.swift

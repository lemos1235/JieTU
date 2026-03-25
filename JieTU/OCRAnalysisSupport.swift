//
//  OCRAnalysisSupport.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/24.
//

import AppKit
import SwiftUI
import Vision
import VisionKit

// MARK: - Shared image view + hosting

struct CapturedImageView: View {
    let image: NSImage
    let showsBorder: Bool
    private let pinGlow = Color(red: 0.29, green: 0.58, blue: 1.0)

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                if showsBorder {
                    Rectangle()
                        .stroke(pinGlow, lineWidth: 1)
                }
            }
            .shadow(color: showsBorder ? pinGlow : .clear, radius: 4, x: 0, y: 0)
    }
}

final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - OCR (used by SelectionOverlay)

enum OCRAnalysisService {
    private static let analyzer = ImageAnalyzer()
    private static let config: ImageAnalyzer.Configuration = {
        var c = ImageAnalyzer.Configuration([.text, .machineReadableCode])
        c.locales = [
            "ja-JP", "zh-Hans", "zh-Hant",
            "ko-KR", "en-US", "fr-FR", "de-DE",
            "es-ES", "it-IT", "pt-BR", "ru-RU",
        ]
        return c
    }()

    static func analyze(
        image: NSImage,
        overlay: ImageAnalysisOverlayView,
        onBarcodes: @escaping @MainActor ([VNBarcodeObservation]) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            async let visionKitResult = analyzer.analyze(image, orientation: .up, configuration: config)

            async let barcodeResult: [VNBarcodeObservation] = {
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else { return [] }
                let request = VNDetectBarcodesRequest()
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                return request.results ?? []
            }()

            do {
                let (analysis, barcodes) = try await (visionKitResult, barcodeResult)
                await MainActor.run {
                    overlay.analysis = analysis
                    onBarcodes(barcodes)
                }
            } catch {
                NSLog("OCR analysis failed: \(error.localizedDescription)")
            }
        }
    }
}

final class OCRAnalysisContainerView: NSView, ImageAnalysisOverlayViewDelegate {
    let hostingView: PassiveHostingView<CapturedImageView>
    let analysisOverlay = ImageAnalysisOverlayView()

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let imageSize: CGSize
    private let capturedImage: NSImage
    let barcodeAnnotationView = BarcodeAnnotationView()

    // Drag state for middle-button and Option+left drag
    private var dragStartWindowOrigin: CGPoint = .zero
    private var dragStartMouseScreen: CGPoint = .zero
    private var isDragging = false

    init(image: NSImage, showsBorder: Bool = false) {
        capturedImage = image
        imageSize = image.size
        hostingView = PassiveHostingView(
            rootView: CapturedImageView(image: image, showsBorder: showsBorder)
        )
        super.init(frame: .zero)

        analysisOverlay.delegate = self
        analysisOverlay.preferredInteractionTypes = .textSelection
        analysisOverlay.isSupplementaryInterfaceHidden = true
        analysisOverlay.setSupplementaryInterfaceHidden(true, animated: false)

        addSubview(hostingView)
        addSubview(analysisOverlay)
        addSubview(barcodeAnnotationView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func beginAnalysis() {
        OCRAnalysisService.analyze(image: capturedImage, overlay: analysisOverlay) { [weak self] barcodes in
            self?.barcodeAnnotationView.update(barcodes: barcodes)
        }
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        let imageRect = aspectFitRect(for: imageSize, in: bounds)
        analysisOverlay.frame = imageRect
        barcodeAnnotationView.frame = imageRect
    }

    // MARK: ImageAnalysisOverlayViewDelegate

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        updatedMenuFor _: NSMenu,
        for _: NSEvent,
        at point: CGPoint
    ) -> NSMenu {
        let menu = NSMenu()

        // point is in analysisOverlay coordinates == barcodeAnnotationView coordinates
        if let barcode = barcodeAnnotationView.barcode(at: point) {
            let payload = barcode.payloadStringValue ?? ""
            let isURL = URL(string: payload)?.scheme != nil
            let title = isURL ? "复制链接" : "复制文本"
            let copyBarcodeItem = NSMenuItem(
                title: title,
                action: #selector(handleCopyBarcodePayload(_:)),
                keyEquivalent: ""
            )
            copyBarcodeItem.target = self
            copyBarcodeItem.representedObject = payload
            menu.addItem(copyBarcodeItem)
            menu.addItem(.separator())
        }

        let selectedText = overlayView.selectedText
        if !selectedText.isEmpty {
            let copyTextItem = NSMenuItem(
                title: "复制当前已选文字",
                action: #selector(handleCopySelectedText),
                keyEquivalent: ""
            )
            copyTextItem.target = self
            menu.addItem(copyTextItem)
            menu.addItem(.separator())
        }

        let copyItem = NSMenuItem(title: "复制当前图像", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "另存为图片", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭该贴图", action: #selector(handleClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        overlayView.setSupplementaryInterfaceHidden(true, animated: false)
    }

    @objc private func handleCopyBarcodePayload(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String, !payload.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    @objc private func handleCopySelectedText() {
        let text = analysisOverlay.selectedText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func handleCopy() {
        onCopy?()
    }

    @objc private func handleSave() {
        onSave?()
    }

    @objc private func handleClose() {
        onClose?()
    }

    // MARK: - Drag to move (middle-button or Option+left)

    // ImageAnalysisOverlayView sits on top and consumes mouse events, so we use a
    // local NSEvent monitor at the window level to intercept drag gestures first.

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        guard window != nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                           .otherMouseDown, .otherMouseDragged, .otherMouseUp]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleLocalEvent(event)
        }
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown where event.modifierFlags.contains(.option):
            beginDrag(event: event)
            return nil // consume; don't pass to overlay
        case .leftMouseDragged:
            if isDragging { continueDrag(); return nil }
        case .leftMouseUp:
            if isDragging { endDrag(); return nil }
        case .otherMouseDown where event.buttonNumber == 2:
            beginDrag(event: event)
            return nil
        case .otherMouseDragged:
            if isDragging { continueDrag(); return nil }
        case .otherMouseUp:
            if isDragging { endDrag(); return nil }
        default:
            break
        }
        return event
    }

    private func beginDrag(event _: NSEvent) {
        guard let win = window else { return }
        isDragging = true
        dragStartWindowOrigin = win.frame.origin
        dragStartMouseScreen = NSEvent.mouseLocation
    }

    private func continueDrag() {
        guard isDragging, let win = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouseScreen.x
        let dy = current.y - dragStartMouseScreen.y
        win.setFrameOrigin(CGPoint(
            x: dragStartWindowOrigin.x + dx,
            y: dragStartWindowOrigin.y + dy
        ))
    }

    private func endDrag() {
        isDragging = false
    }

    private func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

// MARK: - Barcode annotation overlay

final class BarcodeAnnotationView: NSView {
    private var barcodes: [VNBarcodeObservation] = []
    private var barcodeTrackingAreas: [NSTrackingArea] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only claim hit-testing over actual barcode regions so the
        // ImageAnalysisOverlayView beneath us still receives events elsewhere.
        barcodes.contains { rectForObservation($0).contains(point) } ? self : nil
    }

    func update(barcodes: [VNBarcodeObservation]) {
        self.barcodes = barcodes
        needsDisplay = true
        rebuildTrackingAreas()
    }

    /// Returns the barcode observation whose view-space rect contains `point`,
    /// where `point` is in this view's coordinate space.
    func barcode(at point: CGPoint) -> VNBarcodeObservation? {
        barcodes.first { rectForObservation($0).contains(point) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !barcodes.isEmpty else { return }
        let ctx = NSGraphicsContext.current?.cgContext
        for obs in barcodes {
            let rect = rectForObservation(obs)
            // Subtle fill
            ctx?.setFillColor(NSColor.systemYellow.withAlphaComponent(0.12).cgColor)
            ctx?.fill(rect)
            // Border
            ctx?.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.9).cgColor)
            ctx?.setLineWidth(2)
            ctx?.stroke(rect)
        }
    }

    // MARK: Hover tooltip via tracking areas

    private func rebuildTrackingAreas() {
        for ta in barcodeTrackingAreas { removeTrackingArea(ta) }
        barcodeTrackingAreas.removeAll()
        for obs in barcodes {
            let rect = rectForObservation(obs)
            let ta = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["payload": obs.payloadStringValue ?? ""]
            )
            addTrackingArea(ta)
            barcodeTrackingAreas.append(ta)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        let payload = (event.trackingArea?.userInfo?["payload"] as? String) ?? ""
        toolTip = payload.isEmpty ? nil : payload
    }

    override func mouseExited(with event: NSEvent) {
        toolTip = nil
    }

    // MARK: Coordinate conversion

    /// Converts a `VNBarcodeObservation.boundingBox` (normalized, bottom-left origin)
    /// to this view's coordinate space.
    /// NSView is not flipped (origin at bottom-left, Y axis up), which matches
    /// Vision's normalized coordinate system directly — no Y-flip needed.
    private func rectForObservation(_ obs: VNBarcodeObservation) -> CGRect {
        let vb = obs.boundingBox
        let w = bounds.width
        let h = bounds.height
        return CGRect(
            x: vb.origin.x * w,
            y: vb.origin.y * h,
            width: vb.width * w,
            height: vb.height * h
        )
    }
}

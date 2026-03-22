//
//  SelectionOverlay.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - (SelectionOverlay removed — capture-first flow uses AdjustmentOverlayController directly)

// Placeholder to keep old call sites from compiling if any remain
// (AppDelegate now calls AdjustmentOverlayController.show directly)

// MARK: - Adjustment Overlay (single-stage: frozen screen + live adjustable selection + inline toolbar)

final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

struct MagnifierSnapshot {
    let screenPoint: CGPoint
    let localPoint: CGPoint
    let overlaySize: CGSize
    let croppedImage: CGImage
}

final class OverlayMagnifierPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class OverlayMagnifierView: NSView {
    static let panelSize = CGSize(width: 150, height: 110)
    private let magnifierInset: CGFloat = 8
    private let magnifierCornerRadius: CGFloat = 10

    var snapshot: MagnifierSnapshot? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_: NSRect) {
        guard let snapshot,
              let ctx = NSGraphicsContext.current?.cgContext
        else { return }

        let headerHeight: CGFloat = 22
        let frame = bounds
        let contentRect = CGRect(
            x: frame.minX + magnifierInset,
            y: frame.minY + magnifierInset,
            width: frame.width - magnifierInset * 2,
            height: frame.height - magnifierInset * 2 - headerHeight
        )
        let previousInterpolation = NSGraphicsContext.current?.imageInterpolation
        let outerPath = NSBezierPath(
            roundedRect: frame, xRadius: magnifierCornerRadius, yRadius: magnifierCornerRadius
        )

        ctx.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        outerPath.fill()
        ctx.restoreGState()

        outerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.16).setStroke()
        outerPath.stroke()

        let headerRect = CGRect(
            x: frame.minX + 1,
            y: frame.maxY - headerHeight - 1,
            width: frame.width - 2,
            height: headerHeight
        )
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(
            roundedRect: headerRect,
            xRadius: magnifierCornerRadius - 1,
            yRadius: magnifierCornerRadius - 1
        ).fill()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
        ]
        let coords =
            "\(Int(snapshot.localPoint.x)), \(Int(snapshot.overlaySize.height - snapshot.localPoint.y))"
        (coords as NSString).draw(
            at: CGPoint(x: headerRect.minX + 10, y: headerRect.minY + 5),
            withAttributes: labelAttrs
        )

        let badge = "10×"
        let badgeSize = (badge as NSString).size(withAttributes: labelAttrs)
        (badge as NSString).draw(
            at: CGPoint(x: headerRect.maxX - badgeSize.width - 10, y: headerRect.minY + 5),
            withAttributes: labelAttrs
        )

        ctx.saveGState()
        NSBezierPath(roundedRect: contentRect, xRadius: 8, yRadius: 8).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(
            cgImage: snapshot.croppedImage,
            size: NSSize(width: snapshot.croppedImage.width, height: snapshot.croppedImage.height)
        )
        .draw(in: contentRect)
        ctx.restoreGState()
        NSGraphicsContext.current?.imageInterpolation = previousInterpolation ?? .default

        ctx.saveGState()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: contentRect.midX, y: contentRect.minY))
        ctx.addLine(to: CGPoint(x: contentRect.midX, y: contentRect.maxY))
        ctx.move(to: CGPoint(x: contentRect.minX, y: contentRect.midY))
        ctx.addLine(to: CGPoint(x: contentRect.maxX, y: contentRect.midY))
        ctx.strokePath()

        NSColor.white.withAlphaComponent(0.96).setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: contentRect.midX, y: contentRect.minY))
        ctx.addLine(to: CGPoint(x: contentRect.midX, y: contentRect.maxY))
        ctx.move(to: CGPoint(x: contentRect.minX, y: contentRect.midY))
        ctx.addLine(to: CGPoint(x: contentRect.maxX, y: contentRect.midY))
        ctx.strokePath()

        let centerDot = CGRect(
            x: contentRect.midX - 2.5, y: contentRect.midY - 2.5, width: 5, height: 5
        )
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.95).cgColor)
        ctx.fillEllipse(in: centerDot)

        NSColor.white.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: contentRect, xRadius: 8, yRadius: 8).stroke()
        ctx.restoreGState()
    }
}

final class OverlayToolbarHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with _: NSEvent) {
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.arrow.set()
    }
}

@MainActor
final class AdjustmentOverlayController {
    static var active: AdjustmentOverlayController?

    private let panel: SelectionOverlayPanel
    private let toolbarPanel: NSPanel
    private let magnifierPanel: OverlayMagnifierPanel
    private let adjustView: AdjustmentOverlayView
    private let screen: NSScreen
    private let fullImage: NSImage
    private var resultPanels: [ResultPanel] = []
    private var toolbarHosting: NSHostingView<PinToolbarView>!
    private let magnifierView: OverlayMagnifierView

    static func show(fullImage: NSImage, initialRect: CGRect?, screen: NSScreen) {
        let ctrl = AdjustmentOverlayController(
            fullImage: fullImage, initialRect: initialRect, screen: screen
        )
        active = ctrl
        ctrl.show()
    }

    private init(fullImage: NSImage, initialRect: CGRect?, screen: NSScreen) {
        self.screen = screen
        self.fullImage = fullImage

        // Full-screen frozen image panel
        panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Floating toolbar panel (lives above the full-screen panel)
        toolbarPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toolbarPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        toolbarPanel.isOpaque = false
        toolbarPanel.backgroundColor = .clear
        toolbarPanel.hasShadow = true
        toolbarPanel.isReleasedWhenClosed = false
        toolbarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toolbarPanel.ignoresMouseEvents = false
        toolbarPanel.acceptsMouseMovedEvents = true

        magnifierPanel = OverlayMagnifierPanel(
            contentRect: CGRect(origin: .zero, size: OverlayMagnifierView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        magnifierPanel.level = NSWindow.Level(rawValue: toolbarPanel.level.rawValue + 1)
        magnifierPanel.isOpaque = false
        magnifierPanel.backgroundColor = .clear
        magnifierPanel.hasShadow = false
        magnifierPanel.isReleasedWhenClosed = false
        magnifierPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        magnifierPanel.ignoresMouseEvents = true
        magnifierView = OverlayMagnifierView(
            frame: CGRect(origin: .zero, size: OverlayMagnifierView.panelSize)
        )
        magnifierPanel.contentView = magnifierView

        adjustView = AdjustmentOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            fullImage: fullImage,
            initialRect: initialRect
        )
        panel.contentView = adjustView
    }

    private func show() {
        adjustView.onCancel = { [weak self] in self?.cancel() }
        adjustView.onDragBegan = { [weak self] in self?.toolbarPanel.orderOut(nil) }
        adjustView.onDragEnded = { [weak self] in
            self?.repositionToolbar()
            self?.toolbarPanel.orderFront(nil)
        }
        adjustView.onSelectionChanged = { [weak self] in self?.repositionToolbar() }
        adjustView.onMagnifierChanged = { [weak self] snapshot in self?.updateMagnifier(snapshot) }
        adjustView.shouldUseArrowCursorAtScreenPoint = { [weak self] screenPoint in
            guard let self else { return false }
            return self.toolbarPanel.isVisible && self.toolbarPanel.frame.contains(screenPoint)
        }

        let toolbarView = PinToolbarView(
            onClose: { [weak self] in self?.cancel() },
            onPin: { [weak self] in self?.performPin() },
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave: { [weak self] in self?.performSave() },
            onCopy: { [weak self] in self?.performCopy() }
        )
        toolbarHosting = OverlayToolbarHostingView(rootView: toolbarView)
        toolbarPanel.contentView = toolbarHosting

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(adjustView)
        panel.invalidateCursorRects(for: adjustView)
        magnifierPanel.orderOut(nil)
        // Only show toolbar if we already have a selection; otherwise user draws first
        if adjustView.hasSelection {
            repositionToolbar()
            toolbarPanel.orderFront(nil)
        }
    }

    // MARK: - Toolbar positioning

    private func repositionToolbar() {
        let sel = adjustView.selectionRect
        let screenOrigin = screen.frame.origin
        let toolbarW = toolbarHosting.fittingSize.width
        let toolbarH = toolbarHosting.fittingSize.height
        let gap: CGFloat = 8
        let x = screenOrigin.x + sel.maxX - toolbarW + 4 // compensate PinToolbarView's 4pt shadow padding
        let y = screenOrigin.y + sel.minY - toolbarH - gap
        toolbarPanel.setFrame(
            CGRect(x: x, y: max(screenOrigin.y + 4, y), width: toolbarW, height: toolbarH),
            display: true
        )
        toolbarHosting.frame = CGRect(
            origin: .zero, size: CGSize(width: toolbarW, height: toolbarH)
        )
    }

    // MARK: - Crop helper

    private func cropCurrentSelection() -> NSImage? {
        let sel = adjustView.selectionRect
        guard let cgFull = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgFull.width) / screen.frame.width
        let scaleY = CGFloat(cgFull.height) / screen.frame.height
        let cropCG = CGRect(
            x: sel.minX * scaleX,
            y: (screen.frame.height - sel.maxY) * scaleY,
            width: sel.width * scaleX,
            height: sel.height * scaleY
        )
        guard let cropped = cgFull.cropping(to: cropCG) else { return nil }
        return NSImage(cgImage: cropped, size: sel.size)
    }

    // MARK: - Actions

    private func cancel() {
        resultPanels.forEach { $0.close() }
        resultPanels = []
        magnifierPanel.orderOut(nil)
        toolbarPanel.orderOut(nil)
        panel.orderOut(nil)
        AdjustmentOverlayController.active = nil
    }

    private func updateMagnifier(_ snapshot: MagnifierSnapshot?) {
        guard let snapshot else {
            magnifierView.snapshot = nil
            magnifierPanel.orderOut(nil)
            return
        }

        magnifierView.snapshot = snapshot
        magnifierPanel.setFrame(
            CGRect(
                origin: magnifierOrigin(near: snapshot.screenPoint),
                size: OverlayMagnifierView.panelSize
            ),
            display: true
        )
        magnifierPanel.orderFront(nil)
    }

    private func magnifierOrigin(near point: CGPoint) -> CGPoint {
        let size = OverlayMagnifierView.panelSize
        let offset = CGPoint(x: 18, y: -18)
        var origin = CGPoint(x: point.x + offset.x, y: point.y - size.height + offset.y)
        if origin.x + size.width > screen.frame.maxX - 8 {
            origin.x = point.x - size.width - offset.x
        }
        if origin.y < screen.frame.minY + 8 {
            origin.y = point.y - offset.y
        }
        origin.x = min(max(screen.frame.minX + 8, origin.x), screen.frame.maxX - size.width - 8)
        origin.y = min(max(screen.frame.minY + 8, origin.y), screen.frame.maxY - size.height - 8)
        return origin
    }

    private func performPin() {
        guard let img = cropCurrentSelection() else { return }
        let selectionFrame = CGRect(
            x: screen.frame.origin.x + adjustView.selectionRect.minX,
            y: screen.frame.origin.y + adjustView.selectionRect.minY,
            width: adjustView.selectionRect.width,
            height: adjustView.selectionRect.height
        )
        Task { @MainActor [weak self] in
            PinWindowController.create(image: img, initialFrame: selectionFrame)
            self?.cancel()
        }
    }

    private func performTranslate() {
        guard let img = cropCurrentSelection() else { return }
        Task {
            do {
                let lines = try await OCRManager.recognize(image: img)
                guard !lines.isEmpty else {
                    showResult(text: "未识别到可翻译的文字", title: "翻译")
                    return
                }
                let source = lines.joined(separator: "\n")
                let targetLang =
                    (NSApp.delegate as? AppDelegate)?.targetLanguage
                        ?? Locale.Language(identifier: "zh-Hans")
                let translated = try await TranslationManager.shared.translate(
                    source, to: targetLang
                )
                showResult(text: "原文：\n\(source)\n\n译文：\n\(translated)", title: "翻译结果")
            } catch {
                showResult(text: "翻译失败：\(error.localizedDescription)", title: "翻译")
            }
        }
    }

    private func performSave() {
        guard let img = cropCurrentSelection() else { return }
        // Hide overlay panels so the screen unfreezes, but keep self alive
        magnifierPanel.orderOut(nil)
        toolbarPanel.orderOut(nil)
        panel.orderOut(nil)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "screenshot.png"
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url,
               let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:])
            {
                try? png.write(to: url)
            }
            self?.cancel()
        }
    }

    private func performCopy() {
        guard let img = cropCurrentSelection() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        cancel()
    }

    private func showResult(text: String, title: String) {
        let rp = ResultPanel(text: text, title: title)
        let x = screen.frame.maxX - 340
        let y = screen.frame.midY - 100
        rp.setFrameOrigin(CGPoint(x: x, y: y))
        resultPanels.append(rp)
        rp.makeKeyAndOrderFront(nil)
    }
}

// MARK: - AdjustmentOverlayView

final class AdjustmentOverlayView: NSView {
    var onCancel: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onMagnifierChanged: ((MagnifierSnapshot?) -> Void)?
    var shouldUseArrowCursorAtScreenPoint: ((CGPoint) -> Bool)?

    let fullImage: NSImage
    private let fullCGImage: CGImage?
    private(set) var selectionRect: CGRect
    private var pointerLocation: CGPoint?
    private var trackingArea: NSTrackingArea?

    // MARK: Handle geometry

    private enum Handle: Int, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var cursor: NSCursor {
            switch self {
            case .topLeft, .bottomRight:
                return Handle.diagonalCursor(nwse: true)
            case .topRight, .bottomLeft:
                return Handle.diagonalCursor(nwse: false)
            case .top, .bottom:
                return .resizeUpDown
            case .left, .right:
                return .resizeLeftRight
            }
        }

        /// Load nwse or nesw resize cursor from macOS system resources.
        /// Falls back to arrow if the system cursor cannot be loaded.
        private static func diagonalCursor(nwse: Bool) -> NSCursor {
            let name = nwse ? "resizenorthwestsoutheast" : "resizenortheastsouthwest"
            let base =
                "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors"
            let path = "\(base)/\(name)/cursor.pdf"
            if let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: 20, height: 20)
                return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 10))
            }
            return .arrow
        }
    }

    private let handleRadius: CGFloat = 5
    private let handleHitRadius: CGFloat = 10
    private let magnifierSize = CGSize(width: 150, height: 110)
    private let magnifierInset: CGFloat = 8
    private let magnifierCornerRadius: CGFloat = 10
    private let magnifierOffset = CGPoint(x: 18, y: -18)
    private let magnifierSampleSize = CGSize(width: 14, height: 10)

    // MARK: Drag state

    private enum DragMode {
        case initialDraw(startMouse: CGPoint)
        case move(startRect: CGRect, startMouse: CGPoint)
        case handle(Handle, startRect: CGRect, startMouse: CGPoint)
        case none
    }

    private var dragMode: DragMode = .none
    /// True when no selection exists yet and user must draw the first one
    private var isAwaitingInitialDraw: Bool = false

    /// Whether a valid selection has been drawn
    var hasSelection: Bool {
        !selectionRect.isEmpty
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        false
    } // bottom-left origin, same as NSScreen

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        syncPointerWithMouseLocation()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited,
                .enabledDuringMouseDrag, .cursorUpdate,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    // MARK: Cursor rects

    override func resetCursorRects() {
        guard !isAwaitingInitialDraw, !selectionRect.isEmpty else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        // Handles (take priority — added last so they win in overlap)
        for handle in Handle.allCases {
            let pt = point(for: handle)
            let r = CGRect(
                x: pt.x - handleHitRadius, y: pt.y - handleHitRadius,
                width: handleHitRadius * 2, height: handleHitRadius * 2
            )
            addCursorRect(r, cursor: handle.cursor)
        }
        // Interior (move cursor)
        addCursorRect(selectionRect, cursor: .openHand)
        // Exterior
        addCursorRect(bounds, cursor: .arrow)
    }

    init(frame: NSRect, fullImage: NSImage, initialRect: CGRect?) {
        self.fullImage = fullImage
        fullCGImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let initialRect {
            // initialRect is in global screen coords; offset to view-local
            let screenOrigin = frame.origin
            selectionRect = initialRect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        } else {
            selectionRect = .zero
            isAwaitingInitialDraw = true
        }
        super.init(frame: CGRect(origin: .zero, size: frame.size))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: Drawing

    override func draw(_: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw full-screen background image
        fullImage.draw(in: bounds)

        if !selectionRect.isEmpty {
            // 2. Dim everything outside selection (even-odd punch-out)
            let outer = NSBezierPath(rect: bounds)
            let inner = NSBezierPath(rect: selectionRect)
            outer.windingRule = .evenOdd
            outer.append(inner)
            NSColor.black.withAlphaComponent(0.45).setFill()
            outer.fill()

            // 3. White selection border
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selectionRect)
            border.lineWidth = 1.5
            border.stroke()

            // 4. Draw 8 handles (always visible once a selection exists)
            for handle in Handle.allCases {
                let pt = point(for: handle)
                let dot = CGRect(
                    x: pt.x - handleRadius, y: pt.y - handleRadius,
                    width: handleRadius * 2, height: handleRadius * 2
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.setStrokeColor(NSColor(white: 0.3, alpha: 1).cgColor)
                ctx.setLineWidth(1)
                ctx.fillEllipse(in: dot)
                ctx.strokeEllipse(in: dot)
            }

            // 5. Pixel label
            let label = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let labelSize = (label as NSString).size(withAttributes: attrs)
            let labelX = selectionRect.midX - labelSize.width / 2
            let labelY = selectionRect.maxY + 6
            (label as NSString).draw(at: CGPoint(x: labelX, y: labelY), withAttributes: attrs)
        }
    }

    // MARK: Handle positions

    private func point(for handle: Handle) -> CGPoint {
        let r = selectionRect
        switch handle {
        case .topLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .top: return CGPoint(x: r.midX, y: r.maxY)
        case .topRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottom: return CGPoint(x: r.midX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.minY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func hitTestHandle(_ pt: CGPoint) -> Handle? {
        Handle.allCases.first { h in
            let hp = point(for: h)
            return hypot(pt.x - hp.x, pt.y - hp.y) <= handleHitRadius
        }
    }

    private func hitTestResizeHandle(_ pt: CGPoint) -> Handle? {
        if let handle = hitTestHandle(pt) {
            return handle
        }

        guard !selectionRect.isEmpty else { return nil }

        let r = selectionRect
        let threshold = handleHitRadius
        var matches: [(Handle, CGFloat)] = []

        if pt.y >= r.minY - threshold, pt.y <= r.maxY + threshold {
            let leftDistance = abs(pt.x - r.minX)
            if leftDistance <= threshold {
                matches.append((.left, leftDistance))
            }

            let rightDistance = abs(pt.x - r.maxX)
            if rightDistance <= threshold {
                matches.append((.right, rightDistance))
            }
        }

        if pt.x >= r.minX - threshold, pt.x <= r.maxX + threshold {
            let bottomDistance = abs(pt.y - r.minY)
            if bottomDistance <= threshold {
                matches.append((.bottom, bottomDistance))
            }

            let topDistance = abs(pt.y - r.maxY)
            if topDistance <= threshold {
                matches.append((.top, topDistance))
            }
        }

        return matches.min { $0.1 < $1.1 }?.0
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        updatePointerLocation(with: event)
        let pt = convert(event.locationInWindow, from: nil)
        if isAwaitingInitialDraw {
            dragMode = .initialDraw(startMouse: pt)
            selectionRect = CGRect(origin: pt, size: .zero)
            applyCursor(at: pt)
            notifyMagnifierChanged()
            needsDisplay = true
            return
        }
        if let h = hitTestResizeHandle(pt) {
            dragMode = .handle(h, startRect: selectionRect, startMouse: pt)
        } else if selectionRect.contains(pt) {
            dragMode = .move(startRect: selectionRect, startMouse: pt)
        } else {
            applyCursor(at: pt)
            notifyMagnifierChanged()
            return
        }
        applyCursor(at: pt)
        notifyMagnifierChanged()
        onDragBegan?()
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerLocation(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerLocation(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updatePointerLocation(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updatePointerLocation(with: event)
        let pt = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case let .initialDraw(startMouse):
            selectionRect = rectFrom(startMouse, to: pt)
            notifyMagnifierChanged()
            needsDisplay = true
        case let .move(startRect, startMouse):
            let dx = pt.x - startMouse.x
            let dy = pt.y - startMouse.y
            selectionRect = clamp(startRect.offsetBy(dx: dx, dy: dy))
            notifyMagnifierChanged()
            needsDisplay = true
            onSelectionChanged?()
        case let .handle(h, startRect, startMouse):
            selectionRect = resizedRect(
                startRect: startRect, startMouse: startMouse, currentMouse: pt, handle: h
            )
            notifyMagnifierChanged()
            needsDisplay = true
            onSelectionChanged?()
        case .none:
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        updatePointerLocation(with: event)
        switch dragMode {
        case .initialDraw:
            dragMode = .none
            if selectionRect.width > 4, selectionRect.height > 4 {
                isAwaitingInitialDraw = false
                needsDisplay = true
                invalidateCursors()
                applyCursor(at: convert(event.locationInWindow, from: nil))
                notifyMagnifierChanged()
                onDragEnded?() // triggers toolbar to appear
            } else {
                selectionRect = .zero
                isAwaitingInitialDraw = true
                needsDisplay = true
                invalidateCursors()
                applyCursor(at: convert(event.locationInWindow, from: nil))
                notifyMagnifierChanged()
            }
        case .move, .handle:
            dragMode = .none
            invalidateCursors()
            applyCursor(at: convert(event.locationInWindow, from: nil))
            notifyMagnifierChanged()
            onDragEnded?()
        case .none:
            dragMode = .none
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } // Escape
        else {
            super.keyDown(with: event)
        }
    }

    // MARK: Resize logic

    private func shouldShowMagnifier(at point: CGPoint) -> Bool {
        guard !selectionRect.isEmpty, !isAwaitingInitialDraw else { return true }
        return selectionRect.contains(point)
    }

    private func magnifierCrop(around pointer: CGPoint, from image: CGImage) -> CGImage? {
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let sampleWidth = max(1, round(magnifierSampleSize.width * scaleX))
        let sampleHeight = max(1, round(magnifierSampleSize.height * scaleY))
        let centerX = pointer.x * scaleX
        let centerY = (bounds.height - pointer.y) * scaleY
        let originX = min(max(0, centerX - sampleWidth / 2), CGFloat(image.width) - sampleWidth)
        let originY = min(max(0, centerY - sampleHeight / 2), CGFloat(image.height) - sampleHeight)
        let cropRect = CGRect(x: originX, y: originY, width: sampleWidth, height: sampleHeight)
            .integral
        return image.cropping(to: cropRect)
    }

    private func updatePointerLocation(with event: NSEvent) {
        updatePointerLocation(convert(event.locationInWindow, from: nil))
    }

    private func updatePointerLocation(_ point: CGPoint) {
        let clamped = CGPoint(
            x: min(max(bounds.minX, point.x), bounds.maxX),
            y: min(max(bounds.minY, point.y), bounds.maxY)
        )
        pointerLocation = clamped
        applyCursor(at: clamped)
        notifyMagnifierChanged()
        needsDisplay = true
    }

    private func syncPointerWithMouseLocation() {
        guard let window else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        updatePointerLocation(convert(windowPoint, from: nil))
    }

    private func applyCursor(at point: CGPoint) {
        cursor(for: point).set()
    }

    private func cursor(for point: CGPoint) -> NSCursor {
        if let shouldUseArrowCursorAtScreenPoint,
           shouldUseArrowCursorAtScreenPoint(screenPoint(for: point))
        {
            return .arrow
        }
        if isAwaitingInitialDraw || selectionRect.isEmpty {
            return .crosshair
        }
        if let handle = hitTestResizeHandle(point) {
            return handle.cursor
        }
        if selectionRect.contains(point) {
            if case .move = dragMode {
                return .closedHand
            }
            return .openHand
        }
        return .arrow
    }

    private func screenPoint(for point: CGPoint) -> CGPoint {
        guard let window else { return point }
        return window.convertPoint(toScreen: convert(point, to: nil))
    }

    private func notifyMagnifierChanged() {
        onMagnifierChanged?(currentMagnifierSnapshot())
    }

    private func currentMagnifierSnapshot() -> MagnifierSnapshot? {
        guard let pointerLocation,
              shouldShowMagnifier(at: pointerLocation),
              let fullCGImage,
              let croppedImage = magnifierCrop(around: pointerLocation, from: fullCGImage)
        else { return nil }
        return MagnifierSnapshot(
            screenPoint: screenPoint(for: pointerLocation),
            localPoint: pointerLocation,
            overlaySize: bounds.size,
            croppedImage: croppedImage
        )
    }

    private func resizedRect(
        startRect: CGRect, startMouse: CGPoint,
        currentMouse: CGPoint, handle: Handle
    ) -> CGRect {
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY
        switch handle {
        case .topLeft:
            maxX = startRect.maxX
            maxY = startRect.minY + startRect.height + dy
            minX = startRect.minX + dx
        case .top: maxY = startRect.minY + startRect.height + dy
        case .topRight:
            maxX = startRect.minX + startRect.width + dx
            maxY = startRect.minY + startRect.height + dy
        case .right: maxX = startRect.minX + startRect.width + dx
        case .bottomRight:
            maxX = startRect.minX + startRect.width + dx
            minY = startRect.minY + dy
        case .bottom: minY = startRect.minY + dy
        case .bottomLeft:
            minX = startRect.minX + dx
            minY = startRect.minY + dy
        case .left: minX = startRect.minX + dx
        }
        // Normalize so width/height are always positive
        let x = min(minX, maxX)
        let y = min(minY, maxY)
        let w = abs(maxX - minX)
        let h = abs(maxY - minY)
        return clamp(CGRect(x: x, y: y, width: max(4, w), height: max(4, h)))
    }

    private func invalidateCursors() {
        window?.invalidateCursorRects(for: self)
    }

    private func rectFrom(_ a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        )
    }

    private func clamp(_ r: CGRect) -> CGRect {
        let x = max(0, min(r.origin.x, bounds.width - r.width))
        let y = max(0, min(r.origin.y, bounds.height - r.height))
        return CGRect(
            x: x, y: y, width: min(r.width, bounds.width), height: min(r.height, bounds.height)
        )
    }
}

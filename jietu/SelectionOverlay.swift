//
//  SelectionOverlay.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SelectionOverlay entry point

@MainActor
enum SelectionOverlay {

    static func show(completion: @escaping @MainActor (NSImage?) -> Void) {
        // Cover every screen with one panel per display
        let controllers = NSScreen.screens.map {
            SelectionOverlayController(screen: $0, completion: completion)
        }
        // Retain controllers until dismissed
        SelectionOverlayController.active = controllers
        controllers.forEach { $0.show() }
    }
}

// MARK: - Controller (one per screen)

@MainActor
final class SelectionOverlayController {

    // Retain all active controllers across all screens
    static var active: [SelectionOverlayController] = []

    private let screen: NSScreen
    private let panel: NSPanel
    private let overlayView: SelectionOverlayView
    private let completion: @MainActor (NSImage?) -> Void

    init(screen: NSScreen, completion: @escaping @MainActor (NSImage?) -> Void) {
        self.screen = screen
        self.completion = completion

        panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        overlayView = SelectionOverlayView(frame: screen.frame)
        panel.contentView = overlayView
    }

    func show() {
        overlayView.onSelectionComplete = { [weak self] rect in
            self?.handleSelection(rect)
        }
        overlayView.onCancel = { [weak self] in
            self?.dismissAll(result: nil)
        }
        panel.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    private func handleSelection(_ rect: CGRect) {
        NSCursor.pop()
        let captureScreen = screen
        let captureCompletion = completion
        dismissAll(result: nil)
        Task {
            guard let fullImage = try? await ScreenCaptureManager.captureFullScreen(captureScreen) else {
                captureCompletion(nil)
                return
            }
            AdjustmentOverlayController.show(
                fullImage: fullImage,
                initialRect: rect,
                screen: captureScreen
            )
        }
    }

    private func dismissAll(result: NSImage?) {
        NSCursor.pop()
        for ctrl in SelectionOverlayController.active {
            ctrl.panel.orderOut(nil)
        }
        SelectionOverlayController.active = []
        if let result {
            completion(result)
        }
    }
}

// MARK: - Overlay NSView

final class SelectionOverlayView: NSView {

    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint = .zero
    private var currentRect: CGRect = .zero
    private var isDragging = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(origin: startPoint, size: .zero)
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        currentRect = rectFrom(startPoint, to: current)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let current = convert(event.locationInWindow, from: nil)
        let finalRect = rectFrom(startPoint, to: current)

        guard finalRect.width > 4, finalRect.height > 4 else {
            // Too small — cancel
            onCancel?()
            return
        }

        // Convert from view-local (flipped=false) to screen coordinates
        let screenRect = window.map { win in
            win.convertToScreen(convert(finalRect, to: nil))
        } ?? finalRect

        onSelectionComplete?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard isDragging, currentRect.width > 1, currentRect.height > 1 else { return }

        // Dim everything outside selection
        let dimColor = NSColor.black.withAlphaComponent(0.35)
        dimColor.setFill()

        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: currentRect).reversed)
        path.fill()

        // Selection border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: currentRect)
        border.lineWidth = 1.5
        border.stroke()

        // Size label
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(currentRect.width * scale)
        let h = Int(currentRect.height * scale)
        let label = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        var labelOrigin = CGPoint(x: currentRect.minX + 4,
                                  y: currentRect.maxY + 4)
        // Keep label inside screen
        if labelOrigin.y + 16 > bounds.maxY { labelOrigin.y = currentRect.minY - 18 }
        str.draw(at: labelOrigin)
    }

    // MARK: Helpers

    private func rectFrom(_ a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

// NSBezierPath reversed helper for punch-out fill
private extension NSBezierPath {
    var reversed: NSBezierPath {
        let mutable = NSBezierPath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0 ..< elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:  mutable.move(to: points[0])
            case .lineTo:  mutable.line(to: points[0])
            case .curveTo: mutable.curve(to: points[2], controlPoint1: points[0], controlPoint2: points[1])
            case .closePath: mutable.close()
            case .cubicCurveTo: mutable.curve(to: points[2], controlPoint1: points[0], controlPoint2: points[1])
            case .quadraticCurveTo: mutable.line(to: points[1])
            @unknown default: break
            }
        }
        // Wind in the opposite direction so the even-odd rule creates a cutout
        mutable.windingRule = .evenOdd
        return mutable
    }
}

// MARK: - Adjustment Overlay (single-stage: frozen screen + live adjustable selection + inline toolbar)

@MainActor
final class AdjustmentOverlayController {

    static var active: AdjustmentOverlayController?

    private let panel: NSPanel
    private let toolbarPanel: NSPanel
    private let adjustView: AdjustmentOverlayView
    private let screen: NSScreen
    private let fullImage: NSImage
    private var resultPanels: [ResultPanel] = []
    private var toolbarHosting: NSHostingView<PinToolbarView>!

    static func show(fullImage: NSImage, initialRect: CGRect, screen: NSScreen) {
        let ctrl = AdjustmentOverlayController(
            fullImage: fullImage, initialRect: initialRect, screen: screen
        )
        active = ctrl
        ctrl.show()
    }

    private init(fullImage: NSImage, initialRect: CGRect, screen: NSScreen) {
        self.screen = screen
        self.fullImage = fullImage

        // Full-screen frozen image panel
        panel = NSPanel(
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

        adjustView = AdjustmentOverlayView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            fullImage: fullImage,
            initialRect: initialRect
        )
        panel.contentView = adjustView
    }

    private func show() {
        adjustView.onCancel         = { [weak self] in self?.cancel() }
        adjustView.onDragBegan      = { [weak self] in self?.toolbarPanel.orderOut(nil) }
        adjustView.onDragEnded      = { [weak self] in
            self?.repositionToolbar()
            self?.toolbarPanel.orderFront(nil)
        }
        adjustView.onSelectionChanged = { [weak self] in self?.repositionToolbar() }

        let toolbarView = PinToolbarView(
            onClose:     { [weak self] in self?.cancel() },
            onOCR:       { [weak self] in self?.performOCR() },
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave:      { [weak self] in self?.performSave() },
            onCopy:      { [weak self] in self?.performCopy() }
        )
        toolbarHosting = NSHostingView(rootView: toolbarView)
        toolbarHosting.frame = CGRect(x: 0, y: 0, width: 220, height: 44)
        toolbarPanel.contentView = toolbarHosting

        panel.makeKeyAndOrderFront(nil)
        repositionToolbar()
        toolbarPanel.orderFront(nil)
        NSCursor.crosshair.push()
    }

    // MARK: - Toolbar positioning

    private func repositionToolbar() {
        let sel = adjustView.selectionRect
        let screenOrigin = screen.frame.origin
        let toolbarW: CGFloat = 220
        let toolbarH: CGFloat = 44
        let gap: CGFloat = 8
        let x = screenOrigin.x + sel.maxX - toolbarW
        let y = screenOrigin.y + sel.minY - toolbarH - gap
        toolbarPanel.setFrame(
            CGRect(x: x, y: max(screenOrigin.y + 4, y), width: toolbarW, height: toolbarH),
            display: true
        )
    }

    // MARK: - Crop helper

    private func cropCurrentSelection() -> NSImage? {
        let sel = adjustView.selectionRect
        guard let cgFull = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(cgFull.width)  / screen.frame.width
        let scaleY = CGFloat(cgFull.height) / screen.frame.height
        let cropCG = CGRect(
            x: sel.minX * scaleX,
            y: (screen.frame.height - sel.maxY) * scaleY,
            width:  sel.width  * scaleX,
            height: sel.height * scaleY
        )
        guard let cropped = cgFull.cropping(to: cropCG) else { return nil }
        return NSImage(cgImage: cropped, size: sel.size)
    }

    // MARK: - Actions

    private func cancel() {
        NSCursor.pop()
        resultPanels.forEach { $0.close() }
        resultPanels = []
        toolbarPanel.orderOut(nil)
        panel.orderOut(nil)
        AdjustmentOverlayController.active = nil
    }

    private func performOCR() {
        guard let img = cropCurrentSelection() else { return }
        Task {
            do {
                let lines = try await OCRManager.recognize(image: img)
                let text = lines.isEmpty ? "未识别到文字" : lines.joined(separator: "\n")
                showResult(text: text, title: "OCR 识别结果")
            } catch {
                showResult(text: "OCR 失败：\(error.localizedDescription)", title: "OCR")
            }
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
                let targetLang = (NSApp.delegate as? AppDelegate)?.targetLanguage
                    ?? Locale.Language(identifier: "zh-Hans")
                let translated = try await TranslationManager.shared.translate(source, to: targetLang)
                showResult(text: "原文：\n\(source)\n\n译文：\n\(translated)", title: "翻译结果")
            } catch {
                showResult(text: "翻译失败：\(error.localizedDescription)", title: "翻译")
            }
        }
    }

    private func performSave() {
        guard let img = cropCurrentSelection() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "screenshot.png"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }

    private func performCopy() {
        guard let img = cropCurrentSelection() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
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

    var onCancel:           (() -> Void)?
    var onDragBegan:        (() -> Void)?
    var onDragEnded:        (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    let fullImage: NSImage
    private(set) var selectionRect: CGRect

    // MARK: Handle geometry
    private enum Handle: Int, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }
    private let handleRadius: CGFloat = 5
    private let handleHitRadius: CGFloat = 10

    // MARK: Drag state
    private enum DragMode {
        case move(startRect: CGRect, startMouse: CGPoint)
        case handle(Handle, startRect: CGRect, startMouse: CGPoint)
        case none
    }
    private var dragMode: DragMode = .none

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }  // bottom-left origin, same as NSScreen

    init(frame: NSRect, fullImage: NSImage, initialRect: CGRect) {
        self.fullImage = fullImage
        // initialRect is in global screen coords; offset to view-local
        let screenOrigin = frame.origin
        self.selectionRect = initialRect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        super.init(frame: CGRect(origin: .zero, size: frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw full-screen background image
        fullImage.draw(in: bounds)

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

        // 4. Draw 8 handles
        for handle in Handle.allCases {
            let pt = point(for: handle)
            let dot = CGRect(x: pt.x - handleRadius, y: pt.y - handleRadius,
                             width: handleRadius * 2, height: handleRadius * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor(white: 0.3, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            ctx.fillEllipse(in: dot)
            ctx.strokeEllipse(in: dot)
        }

        // 5. Pixel label above selection
        let label = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelX = selectionRect.midX - labelSize.width / 2
        let labelY = selectionRect.maxY + 6
        (label as NSString).draw(at: CGPoint(x: labelX, y: labelY), withAttributes: attrs)
    }

    // MARK: Handle positions

    private func point(for handle: Handle) -> CGPoint {
        let r = selectionRect
        switch handle {
        case .topLeft:     return CGPoint(x: r.minX, y: r.maxY)
        case .top:         return CGPoint(x: r.midX, y: r.maxY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.maxY)
        case .right:       return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottom:      return CGPoint(x: r.midX, y: r.minY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.minY)
        case .left:        return CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func hitTestHandle(_ pt: CGPoint) -> Handle? {
        Handle.allCases.first { h in
            let hp = point(for: h)
            return hypot(pt.x - hp.x, pt.y - hp.y) <= handleHitRadius
        }
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let h = hitTestHandle(pt) {
            dragMode = .handle(h, startRect: selectionRect, startMouse: pt)
        } else if selectionRect.contains(pt) {
            dragMode = .move(startRect: selectionRect, startMouse: pt)
        } else {
            dragMode = .none
            return
        }
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .move(let startRect, let startMouse):
            let dx = pt.x - startMouse.x
            let dy = pt.y - startMouse.y
            selectionRect = clamp(startRect.offsetBy(dx: dx, dy: dy))
        case .handle(let h, let startRect, let startMouse):
            selectionRect = resizedRect(startRect: startRect, startMouse: startMouse, currentMouse: pt, handle: h)
        case .none:
            return
        }
        needsDisplay = true
        onSelectionChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        guard case .none = dragMode else {
            dragMode = .none
            onDragEnded?()
            return
        }
        dragMode = .none
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }  // Escape
        else { super.keyDown(with: event) }
    }

    // MARK: Resize logic

    private func resizedRect(startRect: CGRect, startMouse: CGPoint,
                              currentMouse: CGPoint, handle: Handle) -> CGRect {
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        var minX = startRect.minX, maxX = startRect.maxX
        var minY = startRect.minY, maxY = startRect.maxY
        switch handle {
        case .topLeft:     maxX = startRect.maxX; maxY = startRect.minY + startRect.height + dy; minX = startRect.minX + dx
        case .top:         maxY = startRect.minY + startRect.height + dy
        case .topRight:    maxX = startRect.minX + startRect.width + dx; maxY = startRect.minY + startRect.height + dy
        case .right:       maxX = startRect.minX + startRect.width + dx
        case .bottomRight: maxX = startRect.minX + startRect.width + dx; minY = startRect.minY + dy
        case .bottom:      minY = startRect.minY + dy
        case .bottomLeft:  minX = startRect.minX + dx; minY = startRect.minY + dy
        case .left:        minX = startRect.minX + dx
        }
        // Normalize so width/height are always positive
        let x = min(minX, maxX), y = min(minY, maxY)
        let w = abs(maxX - minX), h = abs(maxY - minY)
        return clamp(CGRect(x: x, y: y, width: max(4, w), height: max(4, h)))
    }

    private func clamp(_ r: CGRect) -> CGRect {
        let x = max(0, min(r.origin.x, bounds.width  - r.width))
        let y = max(0, min(r.origin.y, bounds.height - r.height))
        return CGRect(x: x, y: y, width: min(r.width, bounds.width), height: min(r.height, bounds.height))
    }
}

//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private static var all: [PinWindowController] = []

    private let image: NSImage
    private let imageView: PinImageContainerView

    // MARK: Factory

    static func create(image: NSImage, initialFrame: CGRect? = nil) {
        let ctrl = PinWindowController(image: image, initialFrame: initialFrame)
        all.append(ctrl)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.showWindow(nil)
        ctrl.window?.orderFrontRegardless()
        ctrl.window?.makeKeyAndOrderFront(nil)
        ctrl.imageView.beginAnalysis()
    }

    // MARK: Init

    init(image: NSImage, initialFrame: CGRect? = nil) {
        self.image = image
        imageView = PinImageContainerView(image: image)

        let windowFrame: CGRect
        if let initialFrame {
            windowFrame = initialFrame
        } else {
            // Size pin window to image (max 60% of screen)
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let maxSize = CGSize(
                width: screen.visibleFrame.width * 0.6,
                height: screen.visibleFrame.height * 0.6
            )
            let scale = min(
                1.0,
                min(
                    maxSize.width / image.size.width,
                    maxSize.height / image.size.height
                )
            )
            let winSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            windowFrame = CGRect(
                x: screen.visibleFrame.midX - winSize.width / 2,
                y: screen.visibleFrame.midY - winSize.height / 2,
                width: winSize.width,
                height: winSize.height
            )
        }

        let panel = PinWindow(contentRect: windowFrame)
        super.init(window: panel)

        panel.delegate = self
        panel.contentView = imageView

        imageView.onCopy = { [weak self] in self?.copyImage() }
        imageView.onSave = { [weak self] in self?.saveImage() }
        imageView.onClose = { [weak self] in self?.closePin() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_: Notification) {
        PinWindowController.all.removeAll { $0 === self }
    }

    // MARK: - Actions

    private func closePin() {
        window?.close()
    }

    private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot.png"
        if let win = window {
            panel.level = NSWindow.Level(rawValue: win.level.rawValue + 1)
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let tiff = self.image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:])
            {
                try? png.write(to: url)
            }
        }
    }
}

// MARK: - SwiftUI image view

struct PinImageView: View {
    let image: NSImage
    private let pinGlow = Color(red: 0.29, green: 0.58, blue: 1.0)

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay(
                Rectangle()
                    .stroke(pinGlow, lineWidth: 1)
                    .shadow(color: pinGlow, radius: 4, x: 0, y: 0)
            )
    }
}

final class PinImageContainerView: NSView, ImageAnalysisOverlayViewDelegate {
    private struct WindowDragState {
        let initialMouseLocation: CGPoint
        let initialWindowOrigin: CGPoint
    }

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let hostingView: PassiveHostingView<PinImageView>
    private let imageSize: CGSize
    private let capturedImage: NSImage

    private let analysisOverlay = ImageAnalysisOverlayView()
    private var localEventMonitors: [Any] = []
    private var activeWindowDragState: WindowDragState?
    private var selectedTextForMenu: String?

    init(image: NSImage) {
        capturedImage = image
        imageSize = image.size
        hostingView = PassiveHostingView(rootView: PinImageView(image: image))
        super.init(frame: .zero)

        analysisOverlay.delegate = self
        analysisOverlay.preferredInteractionTypes = .textSelection
        analysisOverlay.isSupplementaryInterfaceHidden = true
        analysisOverlay.setSupplementaryInterfaceHidden(true, animated: false)

        addSubview(hostingView)
        addSubview(analysisOverlay)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        removeEventMonitors()
    }

    // MARK: Analysis

    func beginAnalysis() {
        let config = ImageAnalyzer.Configuration([.text])
        let image = capturedImage
        let overlay = analysisOverlay
        Task.detached(priority: .userInitiated) {
            if let analysis = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: config) {
                await MainActor.run { overlay.analysis = analysis }
            }
        }
    }

    // MARK: Layout

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Let the Live Text overlay handle regular text interactions.
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        analysisOverlay.frame = aspectFitRect(for: imageSize, in: bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitorsIfNeeded()
        }
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

    // MARK: Context menu

    override func menu(for _: NSEvent) -> NSMenu? {
        makeContextMenu()
    }

    private func showContextMenu(with event: NSEvent) {
        endWindowDrag()
        let selectedText = analysisOverlay.hasActiveTextSelection ? analysisOverlay.selectedText : ""
        selectedTextForMenu = selectedText.isEmpty ? nil : selectedText
        analysisOverlay.setSupplementaryInterfaceHidden(true, animated: false)
        let menu = makeContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func contentView(for _: ImageAnalysisOverlayView) -> NSView? {
        hostingView
    }

    func overlayView(_: ImageAnalysisOverlayView, shouldShowMenuForEvent _: NSEvent, atPoint _: CGPoint) -> Bool {
        false
    }

    func overlayView(_: ImageAnalysisOverlayView, updatedMenuFor _: NSMenu, for _: NSEvent, at _: CGPoint) -> NSMenu {
        return NSMenu()
    }

    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        overlayView.setSupplementaryInterfaceHidden(true, animated: false)
    }

    private func installEventMonitorsIfNeeded() {
        guard localEventMonitors.isEmpty else { return }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown],
            handler: { [weak self] event in self?.handleLocalLeftMouseDown(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged],
            handler: { [weak self] event in self?.handleLocalLeftMouseDragged(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp],
            handler: { [weak self] event in self?.handleLocalLeftMouseUp(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown],
            handler: { [weak self] event in self?.handleLocalRightMouseDown(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDown],
            handler: { [weak self] event in self?.handleLocalOtherMouseDown(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseDragged],
            handler: { [weak self] event in self?.handleLocalOtherMouseDragged(event) ?? event }
        ) { localEventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.otherMouseUp],
            handler: { [weak self] event in self?.handleLocalOtherMouseUp(event) ?? event }
        ) { localEventMonitors.append(monitor) }
    }

    private func removeEventMonitors() {
        for monitor in localEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        localEventMonitors.removeAll()
        activeWindowDragState = nil
    }

    private func handleLocalLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard shouldHandleLocalMouseEvent(event) else { return event }

        if event.modifierFlags.contains(.option) {
            beginWindowDrag(with: event)
            return nil
        }

        if event.modifierFlags.contains(.control) {
            showContextMenu(with: event)
            return nil
        }
        return event
    }

    private func handleLocalLeftMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard activeWindowDragState != nil else { return event }
        updateWindowDrag(with: event)
        return nil
    }

    private func handleLocalLeftMouseUp(_ event: NSEvent) -> NSEvent? {
        if activeWindowDragState != nil {
            endWindowDrag()
            return nil
        }
        return event
    }

    private func handleLocalRightMouseDown(_ event: NSEvent) -> NSEvent? {
        guard shouldHandleLocalMouseEvent(event) else { return event }
        showContextMenu(with: event)
        return nil
    }

    private func handleLocalOtherMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2, shouldHandleLocalMouseEvent(event) else { return event }
        beginWindowDrag(with: event)
        return nil
    }

    private func handleLocalOtherMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2, activeWindowDragState != nil else { return event }
        updateWindowDrag(with: event)
        return nil
    }

    private func handleLocalOtherMouseUp(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2, activeWindowDragState != nil else { return event }
        endWindowDrag()
        return nil
    }

    private func shouldHandleLocalMouseEvent(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    private func makeWindowDragState() -> WindowDragState? {
        guard let window else { return nil }
        return WindowDragState(
            initialMouseLocation: NSEvent.mouseLocation,
            initialWindowOrigin: window.frame.origin
        )
    }

    private func beginWindowDrag(with _: NSEvent) {
        activeWindowDragState = makeWindowDragState()
    }

    private func updateWindowDrag(with _: NSEvent) {
        guard let window, let activeWindowDragState else { return }
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - activeWindowDragState.initialMouseLocation.x
        let deltaY = currentMouseLocation.y - activeWindowDragState.initialMouseLocation.y
        let newOrigin = CGPoint(
            x: activeWindowDragState.initialWindowOrigin.x + deltaX,
            y: activeWindowDragState.initialWindowOrigin.y + deltaY
        )
        window.setFrameOrigin(newOrigin)
    }

    private func endWindowDrag() {
        activeWindowDragState = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        if selectedTextForMenu != nil {
            let copySelectedTextItem = NSMenuItem(
                title: "复制选中文本",
                action: #selector(handleCopySelectedText),
                keyEquivalent: ""
            )
            copySelectedTextItem.target = self
            menu.addItem(copySelectedTextItem)
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

    @objc
    private func handleCopy() {
        onCopy?()
    }

    @objc
    private func handleCopySelectedText() {
        guard let text = selectedTextForMenu else { return }
        selectedTextForMenu = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc
    private func handleSave() {
        onSave?()
    }

    @objc
    private func handleClose() {
        onClose?()
    }
}

final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Result Panel

/// A lightweight floating panel that shows OCR / translation text results.
final class ResultPanel: NSPanel {
    init(text: String, title: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.title = title
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces]
        let textView = NSTextView()
        textView.string = text
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        contentView = scroll
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - Controller

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {

    private static var all: [PinWindowController] = []

    private let image: NSImage
    private let toolbarPanel: PinToolbarPanel
    private var toolbarHosting: NSHostingView<PinToolbarView>!
    private var toolbarView: PinToolbarView!
    private var moveObserver: NSObjectProtocol?
    private var resultPanels: [ResultPanel] = []

    // MARK: Factory

    static func create(image: NSImage) {
        let ctrl = PinWindowController(image: image)
        all.append(ctrl)
        ctrl.showWindow(nil)
    }

    // MARK: Init

    init(image: NSImage) {
        self.image = image
        self.toolbarPanel = PinToolbarPanel()

        // Size pin window to image (max 60% of screen)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxSize = CGSize(width: screen.visibleFrame.width * 0.6,
                             height: screen.visibleFrame.height * 0.6)
        let scale = min(1.0, min(maxSize.width / image.size.width,
                                 maxSize.height / image.size.height))
        let winSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let origin = CGPoint(
            x: screen.visibleFrame.midX - winSize.width / 2,
            y: screen.visibleFrame.midY - winSize.height / 2
        )
        let pinWindow = PinWindow(contentRect: CGRect(origin: origin, size: winSize))
        super.init(window: pinWindow)

        // Image content
        let imageView = NSHostingView(rootView: PinImageView(image: image))
        pinWindow.contentView = imageView
        pinWindow.delegate = self

        // Wire drag callbacks for toolbar hide/show
        pinWindow.onDragBegan = { [weak self] in self?.toolbarPanel.orderOut(nil) }
        pinWindow.onDragEnded = { [weak self] in
            self?.repositionToolbar()
            self?.toolbarPanel.orderFront(nil)
        }

        // Build toolbar SwiftUI view (capture self weakly)
        setupToolbar(pinWindow: pinWindow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Toolbar Setup

    private func setupToolbar(pinWindow: PinWindow) {
        let tv = PinToolbarView(
            onClose:     { [weak self] in self?.closePin() },
            onOCR:       { [weak self] in self?.performOCR() },
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave:      { [weak self] in self?.saveImage() },
            onCopy:      { [weak self] in self?.copyImage() }
        )
        self.toolbarView = tv
        let hosting = NSHostingView(rootView: tv)
        self.toolbarHosting = hosting
        toolbarPanel.contentView = hosting

        // Reposition toolbar when window moves (drag callbacks handle hide/show)
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: pinWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repositionToolbar() }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: pinWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repositionToolbar() }
        }
    }

    // MARK: Window lifecycle

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        repositionToolbar()
        toolbarPanel.orderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        toolbarPanel.orderOut(nil)
        if let obs = moveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        resultPanels.forEach { $0.orderOut(nil) }
        PinWindowController.all.removeAll { $0 === self }
    }

    // MARK: Toolbar positioning

    private func repositionToolbar() {
        guard let win = window else { return }
        let toolbarWidth = max(220, min(win.frame.width, 440))
        let toolbarHeight: CGFloat = 52
        let winFrame = win.frame
        let x = winFrame.midX - toolbarWidth / 2
        let y = winFrame.minY - toolbarHeight - 6
        toolbarPanel.setFrame(
            CGRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight),
            display: true
        )
    }

    // MARK: - Toolbar Actions

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
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            if let tiff = self.image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }

    private func performOCR() {
        Task {
            defer { updateToolbarBusy() }
            do {
                let lines = try await OCRManager.recognize(image: image)
                let text = lines.isEmpty ? "未识别到文字" : lines.joined(separator: "\n")
                showResult(text: text, title: "OCR 识别结果")
            } catch {
                showResult(text: "OCR 失败：\(error.localizedDescription)", title: "OCR")
            }
        }
    }

    private func performTranslate() {
        Task {
            defer { updateToolbarBusy() }
            do {
                let lines = try await OCRManager.recognize(image: image)
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

    private func showResult(text: String, title: String) {
        let panel = ResultPanel(text: text, title: title)
        // Position result panel to the right of the pin window
        if let win = window {
            let x = win.frame.maxX + 8
            let y = win.frame.maxY - 200
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        resultPanels.append(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func updateToolbarBusy() {
        // Rebuild toolbar to reset busy spinners
        // SwiftUI state is owned by the view; we signal via a fresh view replacement
        let tv = PinToolbarView(
            onClose:     { [weak self] in self?.closePin() },
            onOCR:       { [weak self] in self?.performOCR() },
            onTranslate: { [weak self] in self?.performTranslate() },
            onSave:      { [weak self] in self?.saveImage() },
            onCopy:      { [weak self] in self?.copyImage() }
        )
        self.toolbarView = tv
        toolbarHosting.rootView = tv
    }
}

// MARK: - SwiftUI image view

struct PinImageView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .overlay(
                GeometryReader { geo in
                    HandlesOverlay(size: geo.size)
                        .allowsHitTesting(false)
                }
                .padding(-3)
                .allowsHitTesting(false)
            )
    }
}

private struct HandlesOverlay: View {
    let size: CGSize
    private let dotSize: CGFloat = 6
    private let color = Color.white.opacity(0.85)
    // Padding applied to the overlay container is 3pt (half dot size),
    // so we offset all positions by +3 to compensate.
    private let pad: CGFloat = 3

    var body: some View {
        let w = size.width
        let h = size.height
        ZStack {
            handle(at: CGPoint(x: pad,           y: pad))
            handle(at: CGPoint(x: w + pad,       y: pad))
            handle(at: CGPoint(x: pad,           y: h + pad))
            handle(at: CGPoint(x: w + pad,       y: h + pad))
            handle(at: CGPoint(x: w / 2 + pad,   y: pad))
            handle(at: CGPoint(x: w / 2 + pad,   y: h + pad))
            handle(at: CGPoint(x: pad,           y: h / 2 + pad))
            handle(at: CGPoint(x: w + pad,       y: h / 2 + pad))
        }
        .frame(width: w + pad * 2, height: h + pad * 2)
    }

    @ViewBuilder
    private func handle(at point: CGPoint) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
            .position(x: point.x, y: point.y)
    }
}

//
//  PinWindowController.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

let kPinContentInset: CGFloat = 6

let kGlowColor = NSColor(red: 0.29, green: 0.58, blue: 1.0, alpha: 1)

/// 固定截图的无边框浮动面板，支持背景拖动并暴露拖动事件回调。
final class PinWindow: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDragBegan?()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onDragEnded?()
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = true
        backgroundColor = .black.withAlphaComponent(0.01)
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// 管理单个固定截图窗口的控制器，负责创建窗口、保存图像、切换 OCR 模式。
@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private static var all: [PinWindowController] = []

    private let image: NSImage
    private let contentContainer: PinContentContainerView

    static func create(image: NSImage, initialFrame: CGRect? = nil, showsOCR: Bool = false) {
        let ctrl = PinWindowController(
            image: image,
            initialFrame: initialFrame,
            showsOCR: showsOCR
        )
        all.append(ctrl)
        ctrl.showWindow(nil)
        ctrl.window?.orderFrontRegardless()
        ctrl.playHighlightAnimation()
        ctrl.beginOCRAnalysisIfNeeded()
    }

    init(image: NSImage, initialFrame: CGRect? = nil, showsOCR: Bool = false) {
        self.image = image

        let windowFrame: CGRect
        if let initialFrame {
            // 先取整到像素边界，防止 NSWindow 产生亚像素偏移
            let rounded = CGRect(
                x: initialFrame.origin.x.rounded(),
                y: initialFrame.origin.y.rounded(),
                width: initialFrame.width.rounded(),
                height: initialFrame.height.rounded()
            )
            // 向外扩展 kPinContentInset，使内部图像视图尺寸与选区完全一致
            windowFrame = rounded.insetBy(dx: -kPinContentInset, dy: -kPinContentInset)
        } else {
            // 按图像大小调整固定窗口（最大为屏幕的 60%）
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
            let origin = CGPoint(
                x: screen.visibleFrame.midX - winSize.width / 2,
                y: screen.visibleFrame.midY - winSize.height / 2
            )
            windowFrame = CGRect(origin: origin, size: winSize)
        }
        let pinWindow = PinWindow(contentRect: windowFrame)
        pinWindow.contentAspectRatio = image.size
        pinWindow.minSize = CGSize(width: 60, height: 60)
        if showsOCR {
            // OCR 模式：左键保留给文本选择；拖动由 OCRAnalysisContainerView 处理
            pinWindow.isMovableByWindowBackground = false
        }
        contentContainer = PinContentContainerView(image: image, showsOCR: showsOCR)
        super.init(window: pinWindow)

        contentContainer.onCopy = { [weak self] in self?.copyImage() }
        contentContainer.onSave = { [weak self] in self?.saveImage() }
        contentContainer.onClose = { [weak self] in self?.closePin() }
        contentContainer.onSwitchToOCR = { [weak self] in self?.enableOCR() }
        contentContainer.wantsLayer = true
        if let layer = contentContainer.layer {
            layer.masksToBounds = false
        }
        pinWindow.contentView = contentContainer
        pinWindow.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func windowWillClose(_: Notification) {
        PinWindowController.all.removeAll { $0 === self }
    }

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

    private func beginOCRAnalysisIfNeeded() {
        contentContainer.beginOCRAnalysis()
    }

    private func playHighlightAnimation() {
        DispatchQueue.main.async { [weak self] in
            self?.contentContainer.playNewPinHighlightAnimation()
        }
    }

    private func enableOCR() {
        // OCR 模式在窗口生命周期内永久生效 — 禁用背景拖动，
        // 防止用户选择文本时意外移动窗口。
        window?.isMovableByWindowBackground = false
        contentContainer.switchToOCR()
        playHighlightAnimation()
    }
}

/// 固定窗口的内容容器，持有图像视图或 OCR 分析视图，并提供右键菜单。
final class PinContentContainerView: NSView {
    var onCopy: (() -> Void)? {
        didSet { ocrContainerView?.onCopy = onCopy }
    }

    var onSave: (() -> Void)? {
        didSet { ocrContainerView?.onSave = onSave }
    }

    var onClose: (() -> Void)? {
        didSet { ocrContainerView?.onClose = onClose }
    }

    var onSwitchToOCR: (() -> Void)?

    private let contentInset: CGFloat = kPinContentInset
    private var currentContentView: NSView
    private var ocrContainerView: OCRAnalysisContainerView?
    private let storedImage: NSImage
    private var isOCRMode: Bool
    private var highlightLayer: CAShapeLayer?
    private var highlightCleanupWorkItem: DispatchWorkItem?

    init(image: NSImage, showsOCR: Bool) {
        storedImage = image
        isOCRMode = showsOCR
        if showsOCR {
            let ocrView = OCRAnalysisContainerView(image: image)
            currentContentView = ocrView
            ocrContainerView = ocrView
        } else {
            let hostingView = NSHostingView(
                rootView: CapturedImageView(image: image)
            )
            currentContentView = hostingView
            ocrContainerView = nil
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(currentContentView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        currentContentView.frame = bounds.insetBy(dx: contentInset, dy: contentInset)
        updateHighlightPathIfNeeded()
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        if !isOCRMode {
            let ocrItem = NSMenuItem(title: "OCR识别", action: #selector(handleSwitchToOCR), keyEquivalent: "")
            ocrItem.target = self
            menu.addItem(ocrItem)
            menu.addItem(.separator())
        }

        let copyItem = NSMenuItem(title: "复制图像", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "图像另存为", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "关闭", action: #selector(handleClose), keyEquivalent: ""
        )
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    @objc
    private func handleSwitchToOCR() {
        onSwitchToOCR?()
    }

    func switchToOCR() {
        guard !isOCRMode else { return }
        isOCRMode = true
        let ocrView = OCRAnalysisContainerView(image: storedImage, showsBorder: true)
        ocrView.onCopy = onCopy
        ocrView.onSave = onSave
        ocrView.onClose = onClose
        ocrContainerView = ocrView
        currentContentView.removeFromSuperview()
        currentContentView = ocrView
        addSubview(currentContentView)
        needsLayout = true
        ocrView.beginAnalysis()
    }

    @objc
    private func handleCopy() {
        onCopy?()
    }

    @objc
    private func handleSave() {
        onSave?()
    }

    @objc
    private func handleClose() {
        onClose?()
    }

    func beginOCRAnalysis() {
        ocrContainerView?.beginAnalysis()
    }

    func playNewPinHighlightAnimation() {
        guard wantsLayer || layer != nil else { return }
        layoutSubtreeIfNeeded()

        highlightCleanupWorkItem?.cancel()
        highlightLayer?.removeFromSuperlayer()

        let layer = CAShapeLayer()
        layer.frame = bounds
        layer.path = highlightPath().cgPath
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = randomHighlightColor().cgColor
        layer.lineWidth = 2
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = 0

        let duration: CFTimeInterval = 1.2

        layer.strokeStart = 0
        layer.strokeEnd = 0
        self.layer?.addSublayer(layer)
        highlightLayer = layer

        let strokeEndAnimation = CABasicAnimation(keyPath: "strokeEnd")
        strokeEndAnimation.fromValue = 0
        strokeEndAnimation.toValue = 1.0

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        strokeEndAnimation.timingFunction = easeOut

        let strokeStartAnimation = CABasicAnimation(keyPath: "strokeStart")
        strokeStartAnimation.fromValue = 0
        strokeStartAnimation.toValue = 0.7
        strokeStartAnimation.beginTime = duration * 0.3
        strokeStartAnimation.timingFunction = easeOut

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = [0, 1, 1, 0]
        opacityAnimation.keyTimes = [0, 0.08, 0.86, 1]

        let group = CAAnimationGroup()
        group.animations = [strokeStartAnimation, strokeEndAnimation, opacityAnimation]
        group.duration = duration
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "new-pin-highlight")

        let cleanup = DispatchWorkItem { [weak self, weak layer] in
            layer?.removeFromSuperlayer()
            guard let self else { return }
            if self.highlightLayer === layer {
                self.highlightLayer = nil
            }
        }
        highlightCleanupWorkItem = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: cleanup)
    }

    private func updateHighlightPathIfNeeded() {
        highlightLayer?.frame = bounds
        highlightLayer?.path = highlightPath().cgPath
    }

    private func highlightPath() -> NSBezierPath {
        let outlineInset = max(2, contentInset * 0.5)
        let rect = currentContentView.frame.insetBy(dx: -outlineInset, dy: -outlineInset)
        return NSBezierPath(rect: rect)
    }

    private func randomHighlightColor() -> NSColor {
        NSColor(
            calibratedHue: CGFloat.random(in: 0..<1),
            saturation: CGFloat.random(in: 0.72...0.92),
            brightness: CGFloat.random(in: 0.9...1.0),
            alpha: 1
        )
    }
}

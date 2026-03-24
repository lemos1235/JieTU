//
//  OCRModule.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/24.
//

import AppKit
import SwiftUI
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
    required init?(coder _: NSCoder) { fatalError() }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - OCR (used by SelectionOverlay)

enum OCRAnalysisService {
    private static let analyzer = ImageAnalyzer()
    private static let config = ImageAnalyzer.Configuration([.text])

    static func analyze(image: NSImage, overlay: ImageAnalysisOverlayView) {
        Task.detached(priority: .userInitiated) {
            do {
                let analysis = try await analyzer.analyze(
                    image,
                    orientation: .up,
                    configuration: config
                )
                await MainActor.run {
                    overlay.analysis = analysis
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

    private let imageSize: CGSize
    private let capturedImage: NSImage

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
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func beginAnalysis() {
        OCRAnalysisService.analyze(image: capturedImage, overlay: analysisOverlay)
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
        analysisOverlay.frame = aspectFitRect(for: imageSize, in: bounds)
    }

    // MARK: ImageAnalysisOverlayViewDelegate

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        updatedMenuFor _: NSMenu,
        for _: NSEvent,
        at _: CGPoint
    ) -> NSMenu {
        NSMenu()
    }

    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        overlayView.setSupplementaryInterfaceHidden(true, animated: false)
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

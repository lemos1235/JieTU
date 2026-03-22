//
//  PinToolbar.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//
//  A floating toolbar panel that attaches below the active image surface.
//  The toolbar contains: close, pin(optional), translate, save, copy.
//

import AppKit
import SwiftUI

// MARK: - Toolbar Panel

final class PinToolbarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool {
        false
    }
}

// MARK: - SwiftUI Toolbar View

struct PinToolbarView: View {
    let onClose: () -> Void
    let onPin: (() -> Void)?
    let onTranslate: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void

    @State private var isTranslateBusy = false

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "xmark", label: "关闭", color: .red) {
                onClose()
            }
            Divider().frame(height: 20).padding(.horizontal, 2)

            if let onPin {
                toolbarButton(icon: "pin.fill", label: "固定", color: .primary) {
                    onPin()
                }
            }

            toolbarButton(
                icon: "globe", label: "翻译", color: .primary,
                busy: isTranslateBusy
            ) {
                isTranslateBusy = true
                onTranslate()
            }
            Divider().frame(height: 20).padding(.horizontal, 2)
            toolbarButton(icon: "square.and.arrow.down", label: "保存", color: .primary) {
                onSave()
            }
            toolbarButton(icon: "doc.on.doc", label: "复制", color: .primary) {
                onCopy()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .padding(4) // so shadow isn't clipped
    }

    func resetBusy() {
        isTranslateBusy = false
    }

    private func toolbarButton(
        icon: String,
        label: String,
        color: Color,
        busy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if busy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 18, height: 18)
                }
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

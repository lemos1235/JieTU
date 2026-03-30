//
//  Toolbar.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import AppKit
import Combine
import SwiftUI

/// 附着在截图选区下方的无边框悬浮面板。
final class ToolbarPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 276, height: 44),
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

/// 工具栏的动态状态，控制可选按钮的显隐。
@MainActor
final class ToolbarModel: ObservableObject {
    @Published var showPin: Bool
    @Published var showOCR: Bool

    init(showPin: Bool, showOCR: Bool) {
        self.showPin = showPin
        self.showOCR = showOCR
    }
}

/// 工具栏 SwiftUI 视图，包含关闭、固定、OCR、保存、复制按钮。
struct ToolbarView: View {
    let onClose: () -> Void
    let onPin: (() -> Void)?
    let onOCR: (() -> Void)?
    let onSave: () -> Void
    let onCopy: () -> Void
    @ObservedObject var model: ToolbarModel

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "xmark", label: "关闭", color: .red) {
                onClose()
            }
            Divider().frame(height: 20).padding(.horizontal, 2)

            if model.showPin, let onPin {
                toolbarButton(icon: "pin.fill", label: "固定", color: .primary) {
                    onPin()
                }
            }

            if model.showOCR, let onOCR {
                toolbarButton(icon: "text.viewfinder", label: "OCR", color: .primary) {
                    onOCR()
                }
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
        .padding(4) // 防止阴影被裁剪
    }

    /// 统一样式的图标+标签按钮。
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

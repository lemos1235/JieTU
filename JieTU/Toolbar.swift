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
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
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

/// 工具栏 SwiftUI 视图，仅图标，黑白高级风格。
struct ToolbarView: View {
    let onClose: () -> Void
    let onPin: (() -> Void)?
    let onOCR: (() -> Void)?
    let onSave: () -> Void
    let onCopy: () -> Void
    @ObservedObject var model: ToolbarModel

    @State private var hovered: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            iconButton(id: "close", icon: "xmark", isDestructive: true, weight: .semibold, action: onClose)

            if model.showPin, let onPin {
                iconButton(id: "pin", icon: "pin.fill", action: onPin)
            }

            if model.showOCR, let onOCR {
                iconButton(id: "ocr", icon: "text.viewfinder", action: onOCR)
            }

            iconButton(id: "save", icon: "arrow.down.to.line", action: onSave)
            iconButton(id: "copy", icon: "doc.on.clipboard", action: onCopy)
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.196, green: 0.196, blue: 0.196, opacity: 0.82))
        }
        .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 5)
        .padding(4) // 防止阴影被裁剪
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(white: 1, opacity: 0.09))
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, 2)
    }

    private func iconButton(
        id: String,
        icon: String,
        isDestructive: Bool = false,
        weight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hovered == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: weight))
                .foregroundStyle(foregroundColor(id: id, isDestructive: isDestructive, isHovered: isHovered))
                .frame(width: 32, height: 28)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(white: 1, opacity: 0.11))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? id : nil }
    }

    private func foregroundColor(id: String, isDestructive: Bool, isHovered: Bool) -> Color {
        if isDestructive {
            return isHovered ? Color(white: 1, opacity: 1.0) : Color(white: 1, opacity: 0.75)
        }
        return isHovered ? Color(white: 1, opacity: 1.0) : Color(white: 1, opacity: 0.85)
    }
}

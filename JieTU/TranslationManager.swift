//
//  TranslationManager.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//
//  Apple Translation framework requires a SwiftUI view to host the TranslationSession.
//  We use a hidden NSHostingController with a carrier SwiftUI view that accepts
//  translation requests via an AsyncStream and returns results via continuations.
//

import AppKit
import Combine
import SwiftUI
@preconcurrency import Translation

@MainActor
final class TranslationManager {
    static let shared = TranslationManager()

    private var hostingController: NSHostingController<TranslationCarrierView>?
    private var carrier: TranslationCarrierView?

    private init() {}

    /// Translate `text` to `targetLanguage`. Source language is auto-detected.
    func translate(_ text: String, to targetLanguage: Locale.Language) async throws -> String {
        // Lazily create the hosting controller that holds the TranslationSession
        if hostingController == nil {
            let view = TranslationCarrierView()
            self.carrier = view
            let hc = NSHostingController(rootView: view)
            hc.view.frame = .zero
            // Attach to a hidden window so the view is in the hierarchy
            let hiddenWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            hiddenWindow.contentViewController = hc
            hiddenWindow.orderOut(nil)
            hostingController = hc
        }

        guard let carrier else { throw TranslationError.notReady }
        return try await carrier.translate(text, to: targetLanguage)
    }

    enum TranslationError: Error {
        case notReady
        case noResult
    }
}

// MARK: - Carrier SwiftUI View

/// A hidden SwiftUI view that hosts a TranslationSession via .translationTask.
@MainActor
struct TranslationCarrierView: View {
    /// Request/response bridge
    private let bridge = TranslationBridge()

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                await bridge.runSession(session)
            }
    }

    func translate(_ text: String, to language: Locale.Language) async throws -> String {
        try await bridge.request(text: text, targetLanguage: language)
    }
}

// MARK: - Bridge (ObservableObject to drive .translationTask)

@MainActor
final class TranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    // Pending request
    private var pendingText: String = ""
    private var pendingLanguage: Locale.Language = .init(identifier: "zh-Hans")
    private var pendingContinuation: CheckedContinuation<String, Error>?

    func request(text: String, targetLanguage: Locale.Language) async throws -> String {
        pendingText = text
        pendingLanguage = targetLanguage
        // Trigger .translationTask by setting/updating configuration
        configuration = TranslationSession.Configuration(
            source: nil,
            target: targetLanguage
        )
        return try await withCheckedThrowingContinuation { cont in
            pendingContinuation = cont
        }
    }

    nonisolated func runSession(_ session: TranslationSession) async {
        let request = await MainActor.run {
            () -> (text: String, continuation: CheckedContinuation<String, Error>)? in
            guard let continuation = pendingContinuation else { return nil }
            let text = pendingText
            pendingContinuation = nil
            return (text, continuation)
        }

        guard let request else { return }

        do {
            let response = try await session.translate(request.text)
            await MainActor.run {
                request.continuation.resume(returning: response.targetText)
                configuration = nil
            }
        } catch {
            await MainActor.run {
                request.continuation.resume(throwing: error)
                configuration = nil
            }
        }
    }
}

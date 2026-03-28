//
//  GlobalHotKeyMonitor.swift
//  JieTU
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import Carbon

@MainActor
final class GlobalHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    private let onKeyDown: @MainActor () -> Void

    init?(id: FourCharCode, keyCode: UInt32, modifiers: UInt32, onKeyDown: @escaping @MainActor () -> Void) {
        hotKeyID = EventHotKeyID(signature: OSType(id), id: UInt32(1))
        self.onKeyDown = onKeyDown

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            NSLog("Failed to install hot key handler: \(handlerStatus)")
            return nil
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            NSLog("Failed to register hot key: \(registerStatus)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var pressedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )

        guard status == noErr else { return status }
        guard pressedHotKeyID.signature == hotKeyID.signature, pressedHotKeyID.id == hotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }

        onKeyDown()
        return noErr
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        // Carbon delivers kEventHotKeyPressed on the main thread via the run loop.
        // assumeIsolated satisfies Swift's actor-isolation model without an extra hop.
        return MainActor.assumeIsolated {
            monitor.handleHotKeyEvent(event)
        }
    }
}

//
//  JieTUApp.swift
//  JieTU
//
//  Created by Alfred Jobs on 2026/3/22.
//

import SwiftUI

@main
struct JieTUApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

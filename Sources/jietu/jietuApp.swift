//
//  jietuApp.swift
//  jietu
//
//  Created by Alfred Jobs on 2026/3/21.
//

import SwiftUI

@main
struct jietuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

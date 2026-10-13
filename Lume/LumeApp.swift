//
//  LumeApp.swift
//  Lume
//
//  Created by zhujiajunup on 2026/2/7.
//

import SwiftUI
import AVFoundation

@main
struct LumeApp: App {
    @UIApplicationDelegateAdaptor(FamilyAppDelegate.self) private var appDelegate

    init() {
        AudioSessionManager.configurePlayback()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

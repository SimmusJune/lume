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
    init() {
        AudioSessionManager.configurePlayback()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

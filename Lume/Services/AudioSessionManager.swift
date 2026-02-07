import AVFoundation
import Foundation
import UIKit

enum AudioSessionManager {
    static func configurePlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            // Best-effort; keep app running even if session config fails.
        }
    }
}

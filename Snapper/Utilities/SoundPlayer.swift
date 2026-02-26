import AppKit

enum SoundPlayer {
    static func playCapture() {
        NSSound(named: "Tink")?.play()
    }
}

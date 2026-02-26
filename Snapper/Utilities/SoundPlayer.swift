import AppKit

enum SoundPlayer {
    private static let fallbackSoundNames: [NSSound.Name] = [
        NSSound.Name("Glass"),
        NSSound.Name("Tink"),
        NSSound.Name("Pop"),
        NSSound.Name("Funk"),
    ]
    private static var activeSound: NSSound?

    static func playCapture(_ captureSound: CaptureSound = .glass) {
        if play(named: captureSound.nsSoundName) {
            return
        }

        for name in fallbackSoundNames where play(named: name) {
            return
        }

        NSSound.beep()
    }

    static func clearActiveSound() {
        activeSound = nil
    }

    private static func play(named soundName: NSSound.Name) -> Bool {
        guard let sound = NSSound(named: soundName) else { return false }
        activeSound = sound
        sound.delegate = SoundDelegate.shared
        return sound.play()
    }
}

private final class SoundDelegate: NSObject, NSSoundDelegate {
    static let shared = SoundDelegate()

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        SoundPlayer.clearActiveSound()
    }
}

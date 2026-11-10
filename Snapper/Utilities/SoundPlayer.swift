import AppKit

enum SoundPlayer {
    private static let fallbackSoundNames: [NSSound.Name] = [
        NSSound.Name("Glass"),
        NSSound.Name("Tink"),
        NSSound.Name("Pop"),
        NSSound.Name("Funk"),
    ]
    /// Every sound that is still playing. NSSound is not kept alive by its own
    /// playback, and captures can overlap, so one slot is not enough.
    private static var activeSounds: [ObjectIdentifier: NSSound] = [:]

    static func playCapture(_ captureSound: CaptureSound = .glass) {
        for path in captureSound.fileCandidates where play(fileAtPath: path) {
            return
        }

        if let name = captureSound.nsSoundName, play(named: name) {
            return
        }

        for name in fallbackSoundNames where play(named: name) {
            return
        }

        NSSound.beep()
    }

    fileprivate static func didFinishPlaying(_ sound: NSSound) {
        activeSounds.removeValue(forKey: ObjectIdentifier(sound))
    }

    private static func play(fileAtPath path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return play(NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true))
    }

    private static func play(named soundName: NSSound.Name) -> Bool {
        // NSSound(named:) hands back one shared instance per name, and play()
        // on it returns false while it is still playing. A copy plays
        // independently, so a capture taken during the previous one's sound
        // still gets the chosen sound instead of falling through the list.
        play(NSSound(named: soundName)?.copy() as? NSSound)
    }

    private static func play(_ sound: NSSound?) -> Bool {
        guard let sound else { return false }
        let key = ObjectIdentifier(sound)
        activeSounds[key] = sound
        sound.delegate = SoundDelegate.shared
        if sound.play() {
            return true
        }
        activeSounds.removeValue(forKey: key)
        return false
    }
}

private final class SoundDelegate: NSObject, NSSoundDelegate {
    static let shared = SoundDelegate()

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        SoundPlayer.didFinishPlaying(sound)
    }
}

import AVFoundation
final class BackgroundAudio {
    static let shared = BackgroundAudio()
    private var player: AVAudioPlayer?
    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1; p.volume = 0.0; p.prepareToPlay(); p.play()
            player = p
        } catch { print("BackgroundAudio error: \(error)") }
    }
    func stop() {
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
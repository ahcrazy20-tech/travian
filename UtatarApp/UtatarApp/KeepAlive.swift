import AVFoundation

// MARK: - KeepAlive
// يخلي التطبيق شغال في الخلفية عن طريق تشغيل صوت صامت (مسموح عليه في
// TrollStore لأن مفيش مراجعة App Store). لازم UIBackgroundModes = audio
// في Info.plist، وده متضاف.
final class KeepAlive: NSObject {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    var isRunning: Bool { player?.isPlaying == true }

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        if let url = Self.silentWavURL() {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1     // تكرار لا نهائي
            player?.volume = 0.01          // صوت صفير ما حدش يسمعه
            player?.play()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// يولّد ملف WAV صامت (ثانية واحدة) في مكان مؤقت.
    private static func silentWavURL() -> URL? {
        let sampleRate = 8000
        let samples = sampleRate // ثانية واحدة
        var data = Data()

        func appendASCII(_ s: String) {
            data.append(s.data(using: .ascii)!)
        }
        func appendU32(_ v: UInt32) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var x = v.littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendU32(UInt32(36 + samples))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendU32(16)             // حجم chunk الفورمات
        appendU16(1)              // PCM
        appendU16(1)              // mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate))
        appendU16(1)              // byte rate alignment
        appendU16(8)              // 8-bit
        appendASCII("data")
        appendU32(UInt32(samples))
        data.append(Data(count: samples)) // عينات صفرية = صمت

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("utatar_silence.wav")
        try? data.write(to: url)
        return url
    }
}

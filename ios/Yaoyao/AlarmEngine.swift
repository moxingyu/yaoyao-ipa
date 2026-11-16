import Foundation
import AVFoundation
import AudioToolbox
import Combine

/// 闹钟引擎：靠后台音频保活，到点循环响铃（锁屏也能响，和系统闹钟一样）
final class AlarmEngine: ObservableObject {
    static let shared = AlarmEngine()

    @Published var ringing = false
    @Published var ringingTitles: [String] = []

    private var keepAlive: AVAudioPlayer?
    private var alarm: AVAudioPlayer?
    private var vibrateTimer: Timer?

    private init() {}

    /// 开启后台保活：循环播放 1 秒静音，让 App 不被系统挂起
    func startKeepAlive() {
        configureSession()
        if let player = keepAlive {
            if !player.isPlaying { player.play() }
            return
        }
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        keepAlive = try? AVAudioPlayer(contentsOf: url)
        keepAlive?.numberOfLoops = -1
        keepAlive?.volume = 0.02
        keepAlive?.play()
    }

    func stopKeepAlive() {
        guard !ringing else { return }
        keepAlive?.stop()
        keepAlive = nil
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func startAlarm(title: String) {
        configureSession()
        startKeepAlive()
        if !ringingTitles.contains(title) {
            ringingTitles.append(title)
        }
        guard !ringing else { return }

        ringing = true
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "m4a") {
            alarm = try? AVAudioPlayer(contentsOf: url)
            alarm?.numberOfLoops = 3      // 25 秒 × 4 遍 ≈ 100 秒后自动停
            alarm?.volume = 1.0
            alarm?.play()
        }
        vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func stopAlarm(title: String? = nil) {
        if let title = title {
            ringingTitles.removeAll { $0 == title }
        } else {
            ringingTitles.removeAll()
        }
        guard ringingTitles.isEmpty else { return }
        alarm?.stop()
        alarm = nil
        vibrateTimer?.invalidate()
        vibrateTimer = nil
        ringing = false
    }

    /// App 在前台时用来判断铃声是否已自然播完
    func refreshIfFinished() {
        guard ringing, let player = alarm else { return }
        if !player.isPlaying {
            stopAlarm()
        }
    }
}

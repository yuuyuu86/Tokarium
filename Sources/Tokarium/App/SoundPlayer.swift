import AVFoundation
import Foundation

/// 効果音。音は scripts/audio/ で MIDI から作ったもの（Resources/Sounds/sfx_*.m4a）。
enum SoundEffect: String, CaseIterable, Identifiable {
    case tap, feed, eat, water, coin, buy, place, error, medicine, sparkle, treasure, fanfare, birth, sad, farewell, click
    var id: String { rawValue }

    /// 同じ音を続けて鳴らすときの最短の間隔（魚が次々に餌を食べても、うるさくならないように）。
    var minInterval: TimeInterval {
        switch self {
        case .eat: return 0.15
        case .tap: return 0.1
        case .coin, .fanfare, .sad: return 1
        default: return 0.05
        }
    }
}

/// BGM。昼の曲と夜の曲。
enum BGMTrack: String {
    case day, night

    /// 水槽が暗くなる時間帯（夕方7時〜朝5時）は夜の曲。
    static func at(_ date: Date, calendar: Calendar = .current) -> BGMTrack {
        let h = calendar.component(.hour, from: date)
        return (5..<19).contains(h) ? .day : .night
    }
}

/// BGM と効果音を鳴らす。
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    struct Config: Equatable {
        var music = true
        var musicVolume = 0.5
        var effects = true
        var effectsVolume = 0.8
        /// 水槽の窓が見えているときだけ BGM を流す。
        var musicOnlyWhenVisible = true
        /// 夜は夜の曲にする。
        var nightMusic = true
    }

    var config = Config() { didSet { if config != oldValue { update() } } }
    /// 水槽の窓が見えているか（MainView が知らせる）。
    var tankVisible = false { didSet { if tankVisible != oldValue { update() } } }
    /// いま流れている曲。
    private(set) var currentTrack: BGMTrack?

    private let directory: URL?
    /// テストなどで音を使わないときは作らない。
    private lazy var engine = AVAudioEngine()
    private var isSetUp = false
    private var musicNodes: [AVAudioPlayerNode] = []
    /// 曲ごとに増やす番号。止めた曲の続きを予約しないために使う。
    private var loopTokens: [Int] = [0, 0]
    private var musicNode = 0
    private var effectNodes: [AVAudioPlayerNode] = []
    private var nextEffectNode = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SoundEffect: Date] = [:]
    private var fades: [Int: Fade] = [:]
    private var fadeTimer: Timer?
    private var trackTimer: Timer?
    private var idleStop: DispatchWorkItem?
    private var effectsBusyUntil = Date.distantPast
    private var configObserver: NSObjectProtocol?

    private struct Fade {
        var from: Float, to: Float, start: Date, duration: TimeInterval
        var stopWhenDone: Bool
    }

    private static let sampleRate = 44100.0
    private let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true)) {
        self.directory = directory.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("bgm_day.m4a").path) ? $0 : nil }
    }

    /// 音のファイルが同梱されているか（テストでは false）。
    var isAvailable: Bool { directory != nil }

    /// 読みこめた効果音の数（テスト用。音は鳴らさない）。
    func preloadEffects() -> Int {
        _ = setUpIfNeeded()
        return buffers.count
    }

    // MARK: 効果音

    /// 効果音を鳴らす。`spontaneous` は操作によらず起きたこと（稚魚・コインなど）で、窓が見えていなければ鳴らさない。
    func play(_ effect: SoundEffect, spontaneous: Bool = false) {
        guard config.effects, config.effectsVolume > 0 else { return }
        if spontaneous && !tankVisible { return }
        let now = Date()
        if let last = lastPlayed[effect], now.timeIntervalSince(last) < effect.minInterval { return }
        guard setUpIfNeeded(), let buffer = buffers[effect], startEngine() else { return }
        lastPlayed[effect] = now
        let node = effectNodes[nextEffectNode]
        nextEffectNode = (nextEffectNode + 1) % effectNodes.count
        node.stop()
        node.volume = effectsGain
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
        let length = Double(buffer.frameLength) / Self.sampleRate
        effectsBusyUntil = max(effectsBusyUntil, now.addingTimeInterval(length))
        scheduleIdleStop()
    }

    // MARK: BGM

    private var wantedTrack: BGMTrack? {
        guard isAvailable, config.music, config.musicVolume > 0 else { return nil }
        if config.musicOnlyWhenVisible && !tankVisible { return nil }
        return config.nightMusic ? BGMTrack.at(Date()) : .day
    }

    private var musicVolume: Float { Float(config.musicVolume) * 0.8 }
    /// 効果音の音量。BGM より前に出すぎないよう、素の音量を半分（約 -6dB）にしている。
    private var effectsGain: Float { Float(config.effectsVolume) * 0.5 }

    /// 設定・窓の見え方・時間帯に合わせて、曲を始める・切りかえる・止める。
    private func update() {
        let want = wantedTrack
        if want != currentTrack {
            switchMusic(to: want)
        } else if currentTrack != nil, fades[musicNode] == nil {
            musicNodes[musicNode].volume = musicVolume
        }
        // 流している間は、昼と夜の切りかわりを1分ごとに確かめる
        if want != nil && trackTimer == nil {
            trackTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        } else if want == nil {
            trackTimer?.invalidate()
            trackTimer = nil
        }
    }

    private func switchMusic(to track: BGMTrack?) {
        // 流れている曲はゆっくり消す
        if currentTrack != nil {
            fade(musicNode, to: 0, duration: 2.5, stopWhenDone: true)
        }
        currentTrack = nil
        guard let track, setUpIfNeeded(), startEngine() else {
            scheduleIdleStop()
            return
        }
        guard let url = directory?.appendingPathComponent("bgm_\(track.rawValue).m4a") else { return }
        let index = 1 - musicNode
        let node = musicNodes[index]
        fades[index] = nil
        loopTokens[index] += 1
        node.stop()
        node.volume = 0
        // 2回分を予約しておき、1回分を読み終えるたびに次を足す（つなぎ目なく繰り返す）
        scheduleLoop(url, node: index, token: loopTokens[index])
        scheduleLoop(url, node: index, token: loopTokens[index])
        node.play()
        musicNode = index
        currentTrack = track
        fade(index, to: musicVolume, duration: 2.5, stopWhenDone: false)
        idleStop?.cancel()
    }

    private func scheduleLoop(_ url: URL, node index: Int, token: Int) {
        guard let file = try? AVAudioFile(forReading: url) else {
            AppLog.error("BGM を読めませんでした: \(url.lastPathComponent)")
            return
        }
        musicNodes[index].scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loopTokens[index] == token else { return }
                self.scheduleLoop(url, node: index, token: token)
            }
        }
    }

    private func fade(_ index: Int, to target: Float, duration: TimeInterval, stopWhenDone: Bool) {
        fades[index] = Fade(from: musicNodes[index].volume, to: target, start: Date(), duration: duration, stopWhenDone: stopWhenDone)
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFades() }
        }
    }

    private func stepFades() {
        let now = Date()
        for (index, f) in fades {
            let p = Float(min(1, now.timeIntervalSince(f.start) / f.duration))
            musicNodes[index].volume = f.from + (f.to - f.from) * p
            if p >= 1 {
                fades[index] = nil
                if f.stopWhenDone {
                    loopTokens[index] += 1
                    musicNodes[index].stop()
                }
            }
        }
        if fades.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
            scheduleIdleStop()
        }
    }

    // MARK: エンジン

    private func setUpIfNeeded() -> Bool {
        guard let directory else { return false }
        if isSetUp { return true }
        isSetUp = true
        for _ in 0..<2 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: stereo)
            musicNodes.append(node)
        }
        // 効果音は重ねて鳴らせるよう、いくつか用意しておく
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: mono)
            effectNodes.append(node)
        }
        for effect in SoundEffect.allCases {
            let url = directory.appendingPathComponent("sfx_\(effect.rawValue).m4a")
            do {
                let file = try AVAudioFile(forReading: url)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
                try file.read(into: buffer)
                if buffer.format.channelCount == 1 { buffers[effect] = buffer }
            } catch {
                AppLog.error("効果音を読めませんでした: \(url.lastPathComponent) \(error.localizedDescription)")
            }
        }
        // イヤホンをつないだときなど、出力先が変わるとエンジンが止まるので、つなぎ直す
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
        }
        return true
    }

    private func startEngine() -> Bool {
        idleStop?.cancel()
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            AppLog.error("音を鳴らせませんでした: \(error.localizedDescription)")
            return false
        }
    }

    /// 何も鳴っていなければ、少ししてからエンジンを止める（電池のため）。
    private func scheduleIdleStop() {
        idleStop?.cancel()
        guard currentTrack == nil, fades.isEmpty, isSetUp else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.currentTrack == nil, self.fades.isEmpty, Date() >= self.effectsBusyUntil else { return }
                self.engine.stop()
            }
        }
        idleStop = item
        let wait = max(1, effectsBusyUntil.timeIntervalSinceNow + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: item)
    }

    private func restartAfterDeviceChange() {
        let track = currentTrack
        for i in musicNodes.indices {
            loopTokens[i] += 1
            musicNodes[i].stop()
        }
        fades.removeAll()
        currentTrack = nil
        AppLog.info("音の出力先が変わりました")
        if track != nil { update() }
    }
}

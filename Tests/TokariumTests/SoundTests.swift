import AVFoundation
import Foundation
import Testing
@testable import Tokarium

private let soundsDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Sounds")

/// 同梱する音がそろっていて、すべて読めること（音は鳴らさない）。
@MainActor
@Test func allSoundsLoad() throws {
    let player = SoundPlayer(directory: soundsDir)
    #expect(player.isAvailable)
    #expect(player.preloadEffects() == SoundEffect.allCases.count)
    for track in ["day", "night"] {
        let file = try AVAudioFile(forReading: soundsDir.appendingPathComponent("bgm_\(track).m4a"))
        #expect(file.processingFormat.channelCount == 2)
        #expect(file.length > 44100 * 60)
    }
}

/// テストなど音のファイルがないときは何もしない。
@MainActor
@Test func missingSoundsAreSilent() {
    let player = SoundPlayer(directory: URL(fileURLWithPath: "/nonexistent"))
    #expect(!player.isAvailable)
    player.play(.coin)
    #expect(player.preloadEffects() == 0)
}

@Test func musicFollowsTimeOfDay() {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    func at(_ h: Int) -> BGMTrack { BGMTrack.at(c.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: h))!, calendar: c) }
    #expect(at(12) == .day)
    #expect(at(5) == .day)
    #expect(at(19) == .night)
    #expect(at(2) == .night)
}

/// 古い設定ファイルでも、音の設定は既定値になる。
@Test func soundSettingsDefaultForOldFiles() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"onboarded":true}"#.utf8))
    #expect(s.musicEnabled && s.effectsEnabled && s.musicOnlyWhenVisible)
    #expect(s.soundConfig.musicVolume == 0.5)
}

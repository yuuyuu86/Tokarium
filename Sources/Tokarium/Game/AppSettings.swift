import Foundation

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case window, desktop
    var id: String { rawValue }
    var label: String { self == .window ? String(localized: "ウィンドウ表示") : String(localized: "デスクトップ表示") }
}

enum DesktopScreens: String, Codable, CaseIterable, Identifiable {
    case main, all
    var id: String { rawValue }
    var label: String { self == .main ? String(localized: "メインのディスプレイのみ") : String(localized: "すべてのディスプレイ（同じ水槽を表示）") }
}

struct AppSettings: Codable, Equatable {
    var onboarded = false
    var displayMode: DisplayMode = .window
    var desktopScreens: DesktopScreens = .main
    var fps: Int = 30
    var enabledSources: Set<String> = []
    var includeEstimated = false
    var styleID = "pixel"
    var notificationsEnabled = true
    /// 時間帯で水槽の明るさを変える。
    var timeOfDay = true
    /// 季節の浮遊物（花びら・葉・マリンスノー）。
    var seasons = true
    /// お世話のリマインド（分: 0〜1439）。
    var remindersEnabled = false
    var reminderTimes: [Int] = [9 * 60, 20 * 60]
    /// iCloud Drive で水槽を同期する。
    var iCloudSync = false
    /// この Mac の識別子（同期でどの Mac が保存したかを見分ける）。
    var machineID = UUID().uuidString
    /// バッテリーや低電力モードのとき、自動で動きを控えめにする。
    var autoPowerSaving = true
    /// 初回のチュートリアルを見終わった。
    var tutorialDone = false
    /// BGM を流す。
    var musicEnabled = true
    var musicVolume = 0.5
    /// 水槽の窓が見えているときだけ BGM を流す。
    var musicOnlyWhenVisible = true
    /// 効果音を鳴らす。
    var effectsEnabled = true
    var effectsVolume = 0.8

    var soundConfig: SoundPlayer.Config {
        SoundPlayer.Config(music: musicEnabled, musicVolume: musicVolume, effects: effectsEnabled, effectsVolume: effectsVolume,
                           musicOnlyWhenVisible: musicOnlyWhenVisible, nightMusic: timeOfDay)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? d.onboarded
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? d.displayMode
        desktopScreens = try c.decodeIfPresent(DesktopScreens.self, forKey: .desktopScreens) ?? d.desktopScreens
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        enabledSources = try c.decodeIfPresent(Set<String>.self, forKey: .enabledSources) ?? d.enabledSources
        includeEstimated = try c.decodeIfPresent(Bool.self, forKey: .includeEstimated) ?? d.includeEstimated
        styleID = try c.decodeIfPresent(String.self, forKey: .styleID) ?? d.styleID
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        timeOfDay = try c.decodeIfPresent(Bool.self, forKey: .timeOfDay) ?? d.timeOfDay
        seasons = try c.decodeIfPresent(Bool.self, forKey: .seasons) ?? d.seasons
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        reminderTimes = try c.decodeIfPresent([Int].self, forKey: .reminderTimes) ?? d.reminderTimes
        iCloudSync = try c.decodeIfPresent(Bool.self, forKey: .iCloudSync) ?? d.iCloudSync
        machineID = try c.decodeIfPresent(String.self, forKey: .machineID) ?? d.machineID
        autoPowerSaving = try c.decodeIfPresent(Bool.self, forKey: .autoPowerSaving) ?? d.autoPowerSaving
        // すでに遊んでいる人にはチュートリアルを出さない
        tutorialDone = try c.decodeIfPresent(Bool.self, forKey: .tutorialDone) ?? onboarded
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? d.musicEnabled
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        musicOnlyWhenVisible = try c.decodeIfPresent(Bool.self, forKey: .musicOnlyWhenVisible) ?? d.musicOnlyWhenVisible
        effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? d.effectsEnabled
        effectsVolume = try c.decodeIfPresent(Double.self, forKey: .effectsVolume) ?? d.effectsVolume
    }
}

struct BugReportRequest: Identifiable {
    let id = UUID()
    var crash: Diagnostics.CrashInfo?
}

/// メニューやキーボードショートカットから画面へ頼む操作。
enum UICommand: Equatable {
    case show(Screen)
    case photo
    case toggleEdit
}

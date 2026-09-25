import Foundation

/// 季節のイベント。期間中だけお店に限定の魚と装飾が並ぶ（買ったものはずっと残る）。
struct SeasonalEvent: Identifiable {
    let id: String
    let name: String
    let symbol: String
    /// 期間（月・日）。年をまたぐ期間にも対応する。
    let start: (month: Int, day: Int)
    let end: (month: Int, day: Int)
    let fish: [String]
    let decorations: [String]

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        let v = (c.month ?? 1) * 100 + (c.day ?? 1)
        let s = start.month * 100 + start.day, e = end.month * 100 + end.day
        return s <= e ? (v >= s && v <= e) : (v >= s || v <= e)
    }

    var periodText: String {
        String(localized: "\(start.month)/\(start.day)〜\(end.month)/\(end.day)")
    }
}

enum SeasonalEvents {
    static let all: [SeasonalEvent] = [
        SeasonalEvent(id: "newyear", name: String(localized: "お正月"), symbol: "sun.horizon.fill",
                      start: (12, 28), end: (1, 7), fish: ["tai"], decorations: ["kagamimochi", "kadomatsu"]),
        SeasonalEvent(id: "summer", name: String(localized: "夏祭り"), symbol: "fireworks",
                      start: (7, 15), end: (8, 31), fish: ["yukatagoldfish"], decorations: ["furin", "yoyo"]),
        SeasonalEvent(id: "halloween", name: String(localized: "ハロウィン"), symbol: "moon.stars.fill",
                      start: (10, 1), end: (10, 31), fish: ["ghostfish"], decorations: ["pumpkin", "ghost"]),
        SeasonalEvent(id: "christmas", name: String(localized: "クリスマス"), symbol: "gift.fill",
                      start: (12, 1), end: (12, 25), fish: ["santafish"], decorations: ["xmastree", "present"]),
    ]

    static func active(on date: Date = Date(), calendar: Calendar = .current) -> SeasonalEvent? {
        all.first { $0.contains(date, calendar: calendar) }
    }

    static func event(_ id: String?) -> SeasonalEvent? { all.first { $0.id == id } }
}

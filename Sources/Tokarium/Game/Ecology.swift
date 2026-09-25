import Foundation

/// 魚どうしの関わり（群れ・相性・掃除役・共生）。
enum Ecology {
    /// 群れで泳ぐ魚。同じ種類が2匹以上いると、先頭の魚についていく。
    static let schooling: Set<String> = ["neon", "cardinal", "rummynose", "rasbora", "zebra", "tigerbarb", "medaka"]

    /// 底の掃除役。1匹ごとに水の汚れる速さが少し下がる。
    static let cleaners: Set<String> = ["cory", "oto", "loach", "pleco"]
    static let cleanerEffectPerFish = 0.08
    static let cleanerEffectMax = 0.3

    /// 仲の悪い組み合わせ（いじめる側 → いじめられる側）。
    static let bullies: [String: Set<String>] = [
        "tigerbarb": ["betta", "angel", "gourami", "guppy"],        // 長いひれをかじる
        "puffer": ["guppy", "betta", "goldfish", "ryukin"],         // ひれをかじる
        "lionfish": ["neon", "cardinal", "rummynose", "medaka", "guppy", "zebra"], // 小さな魚をおびえさせる
        "betta": ["betta"],                                          // ベタどうしはけんかする
    ]
    /// ストレスで体調が下がる速さ（1時間あたり）。
    static let stressHealthLossPerHour = 0.6

    /// 共生: カクレクマノミはイソギンチャクのそばで安心する。
    static let symbiosis: [String: String] = ["clown": "anemone"]

    /// 水の汚れる速さにかける数（掃除役が多いほど小さい）。
    static func waterDecayFactor(_ tank: Tank) -> Double {
        let n = tank.fish.filter { $0.isAlive && cleaners.contains($0.speciesID) }.count
        return 1 - min(cleanerEffectMax, Double(n) * cleanerEffectPerFish)
    }

    /// この魚をいじめる、水槽にいる魚の種類。
    static func bulliesOf(_ fish: Fish, in tank: Tank) -> [String] {
        let living = Set(tank.fish.filter { $0.isAlive && $0.id != fish.id }.map(\.speciesID))
        return living.filter { bullies[$0]?.contains(fish.speciesID) ?? false }.sorted()
    }

    /// この種類を買うと、相性の悪い組み合わせになる相手。
    static func conflicts(buying speciesID: String, into tank: Tank) -> [String] {
        let living = Set(tank.fish.filter(\.isAlive).map(\.speciesID))
        var result: Set<String> = []
        for other in living {
            if bullies[speciesID]?.contains(other) ?? false { result.insert(other) }
            if bullies[other]?.contains(speciesID) ?? false { result.insert(other) }
        }
        return result.sorted()
    }

    /// 種類の特徴（お店や図鑑に出す）。
    static func traits(_ speciesID: String) -> [String] {
        var t: [String] = []
        if schooling.contains(speciesID) { t.append(String(localized: "群れで泳ぐ")) }
        if cleaners.contains(speciesID) { t.append(String(localized: "掃除役")) }
        if bullies[speciesID] != nil { t.append(String(localized: "気が強い")) }
        if let partner = symbiosis[speciesID] { t.append(String(localized: "\(Catalog.decoration(partner).name)が好き")) }
        return t
    }

    /// 魚のいまの様子（ストレス・共生）を言葉で。
    static func mood(_ fish: Fish, in tank: Tank) -> String? {
        guard fish.isAlive else { return nil }
        let bullies = bulliesOf(fish, in: tank)
        if !bullies.isEmpty {
            let names = bullies.map { Catalog.species($0).name }.joined(separator: String(localized: "、"))
            return String(localized: "ストレス（\(names)が苦手）")
        }
        if hasPartner(fish, in: tank) { return String(localized: "安心している") }
        return nil
    }

    /// 共生の相手の装飾が置いてあるか。
    static func hasPartner(_ fish: Fish, in tank: Tank) -> Bool {
        guard let partner = symbiosis[fish.speciesID] else { return false }
        return tank.decorations.contains { $0.isPlaced && $0.kindID == partner }
    }
}

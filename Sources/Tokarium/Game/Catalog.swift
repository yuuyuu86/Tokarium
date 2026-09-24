import Foundation

/// 魚の泳ぐ層。
enum SwimZone: String, Codable {
    case any      // 水槽全体
    case upper    // 上層
    case bottom   // 底付近
}

struct FishSpecies: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let blurb: String
    /// 1秒あたりの基本速度（水槽の幅に対する割合）。
    let speed: Double
    let zone: SwimZone
    /// 寿命（日）。
    let lifespanDays: Double
}

enum DecorationPlacement: String, Codable {
    case floor   // 砂の上
}

struct DecorationKind: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let blurb: String
    /// 泡を出すか。
    let bubbles: Bool
}

enum Catalog {
    static let fish: [FishSpecies] = [
        FishSpecies(id: "neon", name: "ネオンテトラ", price: 30, blurb: "青と赤のラインが光る小さな魚。", speed: 0.09, zone: .any, lifespanDays: 180),
        FishSpecies(id: "guppy", name: "グッピー", price: 40, blurb: "大きな尾びれをひらひらさせる。", speed: 0.07, zone: .upper, lifespanDays: 120),
        FishSpecies(id: "cory", name: "コリドラス", price: 60, blurb: "底をちょこちょこ歩く掃除屋さん。", speed: 0.04, zone: .bottom, lifespanDays: 300),
        FishSpecies(id: "goldfish", name: "金魚", price: 80, blurb: "ぽってりした定番の人気者。", speed: 0.05, zone: .any, lifespanDays: 365),
        FishSpecies(id: "betta", name: "ベタ", price: 120, blurb: "ドレスのようなひれを持つ。", speed: 0.04, zone: .upper, lifespanDays: 150),
        FishSpecies(id: "angel", name: "エンゼルフィッシュ", price: 150, blurb: "縦長の体でゆったり泳ぐ。", speed: 0.045, zone: .any, lifespanDays: 300),
        FishSpecies(id: "clown", name: "カクレクマノミ", price: 180, blurb: "オレンジと白のしま模様。", speed: 0.06, zone: .any, lifespanDays: 365),
        FishSpecies(id: "puffer", name: "ミドリフグ", price: 220, blurb: "まんまるで好奇心旺盛。", speed: 0.035, zone: .any, lifespanDays: 240),
    ]

    static let decorations: [DecorationKind] = [
        DecorationKind(id: "shell", name: "貝がら", price: 10, blurb: "砂の上の小さなアクセント。", bubbles: false),
        DecorationKind(id: "grass", name: "水草", price: 15, blurb: "ゆれる緑の水草。", bubbles: false),
        DecorationKind(id: "rock", name: "岩", price: 20, blurb: "どっしりした石。", bubbles: false),
        DecorationKind(id: "tallgrass", name: "背の高い水草", price: 30, blurb: "水面近くまで伸びる。", bubbles: false),
        DecorationKind(id: "wood", name: "流木", price: 40, blurb: "自然な雰囲気の流木。", bubbles: false),
        DecorationKind(id: "coral", name: "サンゴ", price: 50, blurb: "ピンクの枝サンゴ。", bubbles: false),
        DecorationKind(id: "airstone", name: "エアストーン", price: 60, blurb: "ぷくぷく泡が出る。", bubbles: true),
        DecorationKind(id: "chest", name: "宝箱", price: 90, blurb: "ときどき泡が出る宝箱。", bubbles: true),
        DecorationKind(id: "castle", name: "お城", price: 150, blurb: "水槽の主役になるお城。", bubbles: false),
    ]

    static func species(_ id: String) -> FishSpecies {
        fish.first { $0.id == id } ?? fish[0]
    }

    static func decoration(_ id: String) -> DecorationKind {
        decorations.first { $0.id == id } ?? decorations[0]
    }

    // MARK: 初期状態（確定: 魚1匹 + 装飾少し + 少額）
    static let initialCoins = 50
    static let initialFish = ["neon"]
    static let initialDecorations: [(String, Double)] = [("grass", 0.18), ("rock", 0.72)]

    // MARK: お世話用品

    static let medicinePrice = 25

    // MARK: 水槽の大きさ（拡張を買うと上限が増える）

    static let tankSizes: [TankSize] = [
        TankSize(level: 0, name: "小さな水槽", maxFish: 8, maxDecorations: 10, price: 0),
        TankSize(level: 1, name: "ふつうの水槽", maxFish: 14, maxDecorations: 18, price: 300),
        TankSize(level: 2, name: "大きな水槽", maxFish: 22, maxDecorations: 26, price: 800),
        TankSize(level: 3, name: "特大の水槽", maxFish: 32, maxDecorations: 36, price: 1500),
    ]

    static func tankSize(_ level: Int) -> TankSize {
        tankSizes[min(max(0, level), tankSizes.count - 1)]
    }
}

struct TankSize: Identifiable {
    var id: Int { level }
    let level: Int
    let name: String
    let maxFish: Int
    let maxDecorations: Int
    let price: Int
}

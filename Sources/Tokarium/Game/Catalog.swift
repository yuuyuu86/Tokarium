import CoreGraphics
import Foundation

/// 魚の泳ぐ層。
enum SwimZone: String, Codable {
    case any      // 水槽全体
    case upper    // 上層
    case bottom   // 底付近
}

enum FishRarity: Int, Comparable {
    case common, uncommon, rare
    static func < (a: FishRarity, b: FishRarity) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .common: return String(localized: "ふつう")
        case .uncommon: return String(localized: "めずらしい")
        case .rare: return String(localized: "レア")
        }
    }
}

struct FishSpecies: Identifiable {
    let id: String
    let name: String
    let price: Int
    let blurb: String
    /// 1秒あたりの基本速度（水槽の幅に対する割合）。
    let speed: Double
    let zone: SwimZone
    /// 寿命（日）。
    let lifespanDays: Double
    let design: FishDesign

    var rarity: FishRarity { price >= 300 ? .rare : price >= 120 ? .uncommon : .common }
}

struct DecorationKind: Identifiable {
    let id: String
    let name: String
    let price: Int
    let blurb: String
    /// 泡を出す頻度（0 なら出さない）。
    let bubbles: Double
    /// 水槽のドット数での大きさ。
    let size: CGSize
    let design: DecoDesign
    let category: DecorationCategory
}

enum DecorationCategory: CaseIterable {
    case plant, stone, sea, structure

    var label: String {
        switch self {
        case .plant: return String(localized: "水草")
        case .stone: return String(localized: "石・流木")
        case .sea: return String(localized: "サンゴ・貝")
        case .structure: return String(localized: "置きもの")
        }
    }
}

private func fishDesign(_ build: (inout FishDesign) -> Void) -> FishDesign {
    var d = FishDesign()
    build(&d)
    return d
}

enum Catalog {
    static let fish: [FishSpecies] = [
        // MARK: 淡水の小型魚
        FishSpecies(id: "neon", name: String(localized: "ネオンテトラ"), price: 30, blurb: String(localized: "青と赤のラインが光る小さな魚。"),
                    speed: 0.09, zone: .any, lifespanDays: 180, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.42; $0.tailFrac = 0.22; $0.depth = 0.62
                        $0.back = 0x5A7A8A; $0.body = 0xC8D8E0; $0.bellyColor = 0xE8F0F4; $0.fin = 0xB0C4D0
                        $0.patterns = [.hBand(y: -0.15, thickness: 0.4, color: 0x3FD8FF), .lowerRear(color: 0xFF3050, from: 0.6)]
                    }),
        FishSpecies(id: "cardinal", name: String(localized: "カージナルテトラ"), price: 45, blurb: String(localized: "おなか全体が赤いネオンの仲間。"),
                    speed: 0.09, zone: .any, lifespanDays: 200, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.42; $0.tailFrac = 0.22; $0.depth = 0.64
                        $0.back = 0x4A6A7A; $0.body = 0xC8D8E0; $0.bellyColor = 0xE8F0F4; $0.fin = 0xB0C4D0
                        $0.patterns = [.lowerRear(color: 0xFF2040, from: 1.0), .hBand(y: -0.15, thickness: 0.42, color: 0x30C8FF)]
                    }),
        FishSpecies(id: "rummynose", name: String(localized: "ラミーノーズテトラ"), price: 50, blurb: String(localized: "真っ赤な鼻先がトレードマーク。"),
                    speed: 0.1, zone: .any, lifespanDays: 220, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.4; $0.depth = 0.58
                        $0.back = 0x8A9AA0; $0.body = 0xD8E0E4; $0.bellyColor = 0xF4F6F8; $0.fin = 0xE0E8EC
                        $0.patterns = [.head(color: 0xE02030, fraction: 0.32)]
                    }),
        FishSpecies(id: "rasbora", name: String(localized: "ラスボラ"), price: 35, blurb: String(localized: "オレンジの体に黒い三角もよう。"),
                    speed: 0.09, zone: .any, lifespanDays: 200, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.46; $0.depth = 0.64
                        $0.back = 0xC0703A; $0.body = 0xF09860; $0.bellyColor = 0xF8D0B0; $0.fin = 0xF0A070
                        $0.patterns = [.wedge(color: 0x202028)]
                    }),
        FishSpecies(id: "zebra", name: String(localized: "ゼブラダニオ"), price: 30, blurb: String(localized: "青いしまで元気いっぱい。"),
                    speed: 0.12, zone: .upper, lifespanDays: 250, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.36; $0.depth = 0.62; $0.blunt = 0.35
                        $0.back = 0x5A6A78; $0.body = 0xD8DCC8; $0.bellyColor = 0xF0F0E0; $0.fin = 0xC8CCC0
                        $0.patterns = [.hBand(y: -0.45, thickness: 0.18, color: 0x203A8A), .hBand(y: 0.0, thickness: 0.18, color: 0x203A8A),
                                       .hBand(y: 0.45, thickness: 0.18, color: 0x203A8A)]
                    }),
        FishSpecies(id: "medaka", name: String(localized: "ヒメダカ"), price: 25, blurb: String(localized: "水面近くをすいすい泳ぐ。"),
                    speed: 0.08, zone: .upper, lifespanDays: 200, design: fishDesign {
                        $0.length = 11; $0.aspect = 0.36; $0.tail = .round; $0.depth = 0.55; $0.blunt = 0.4
                        $0.back = 0xD8A040; $0.body = 0xF0C060; $0.bellyColor = 0xFFF0C0; $0.fin = 0xF8D890; $0.eyeSize = 1.4
                    }),
        FishSpecies(id: "guppy", name: String(localized: "グッピー"), price: 40, blurb: String(localized: "大きな尾びれをひらひらさせる。"),
                    speed: 0.07, zone: .upper, lifespanDays: 120, design: fishDesign {
                        $0.length = 14; $0.aspect = 0.55; $0.tailFrac = 0.38; $0.tail = .fan; $0.tailSpread = 0.95; $0.depth = 0.45
                        $0.back = 0x9AA888; $0.body = 0xC9D6B0; $0.bellyColor = 0xE8EED8; $0.fin = 0xFF7AA8
                        $0.patterns = [.spots(count: 3, size: 0.06, color: 0x303848)]
                    }),
        FishSpecies(id: "platy", name: String(localized: "プラティ"), price: 35, blurb: String(localized: "まるっこい朱色のアイドル。"),
                    speed: 0.07, zone: .any, lifespanDays: 180, design: fishDesign {
                        $0.length = 12; $0.aspect = 0.55; $0.tail = .round; $0.tailFrac = 0.2; $0.depth = 0.7; $0.blunt = 0.6
                        $0.back = 0xE04020; $0.body = 0xFF6030; $0.bellyColor = 0xFFA070; $0.fin = 0xFF7040
                        $0.patterns = [.rear(color: 0x202028, from: 0.12)]
                    }),
        FishSpecies(id: "molly", name: String(localized: "ブラックモーリー"), price: 45, blurb: String(localized: "つやつやの黒い体。"),
                    speed: 0.07, zone: .any, lifespanDays: 250, design: fishDesign {
                        $0.length = 14; $0.aspect = 0.58; $0.tail = .spade; $0.dorsal = .sail; $0.dorsalHeight = 0.5; $0.depth = 0.62
                        $0.back = 0x14141A; $0.body = 0x2A2A34; $0.bellyColor = 0x3A3A48; $0.fin = 0x30303A; $0.iris = 0xC0A040
                    }),
        FishSpecies(id: "tigerbarb", name: String(localized: "スマトラ"), price: 45, blurb: String(localized: "黒いしまと赤いひれ。"),
                    speed: 0.1, zone: .any, lifespanDays: 300, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.6; $0.depth = 0.75; $0.blunt = 0.55
                        $0.back = 0xC0A040; $0.body = 0xE8C860; $0.bellyColor = 0xF8E8B0; $0.fin = 0xE04020
                        $0.patterns = [.vStripes(count: 4, width: 0.08, color: 0x101010, from: 0.02, to: 0.92)]
                    }),
        FishSpecies(id: "gourami", name: String(localized: "ドワーフグラミー"), price: 70, blurb: String(localized: "青と赤のしまが美しい。"),
                    speed: 0.05, zone: .upper, lifespanDays: 300, design: fishDesign {
                        $0.length = 14; $0.aspect = 0.72; $0.tail = .round; $0.dorsal = .long; $0.anal = .long; $0.analHeight = 0.45
                        $0.filaments = true; $0.depth = 0.62
                        $0.back = 0x2050A0; $0.body = 0x3A70D0; $0.bellyColor = 0x6090E0; $0.fin = 0x5080D0
                        $0.patterns = [.vStripes(count: 7, width: 0.06, color: 0xE04030, from: 0.05, to: 0.9)]
                    }),
        FishSpecies(id: "ram", name: String(localized: "ラミレジィ"), price: 90, blurb: String(localized: "宝石のようなミニシクリッド。"),
                    speed: 0.05, zone: .any, lifespanDays: 250, design: fishDesign {
                        $0.length = 12; $0.aspect = 0.62; $0.tail = .round; $0.dorsal = .long; $0.dorsalHeight = 0.4; $0.depth = 0.72
                        $0.back = 0xD0A030; $0.body = 0xE8D060; $0.bellyColor = 0xF8F0B0; $0.fin = 0x60A0E0
                        $0.patterns = [.head(color: 0xF08030, fraction: 0.32), .spots(count: 4, size: 0.05, color: 0x102060)]
                    }),
        // MARK: 底の魚
        FishSpecies(id: "cory", name: String(localized: "コリドラス"), price: 60, blurb: String(localized: "底をちょこちょこ歩く掃除屋さん。"),
                    speed: 0.04, zone: .bottom, lifespanDays: 300, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.45; $0.tailFrac = 0.2; $0.depth = 0.7; $0.blunt = 0.8; $0.belly = 0.7
                        $0.back = 0x8A7A60; $0.body = 0xC8B89A; $0.bellyColor = 0xEFE3C6; $0.fin = 0xB8A888; $0.barbels = true
                        $0.dorsalHeight = 0.5
                        $0.patterns = [.spots(count: 8, size: 0.04, color: 0x5B4A38)]
                    }),
        FishSpecies(id: "oto", name: String(localized: "オトシンクルス"), price: 55, blurb: String(localized: "ガラスや葉にはりつくコケ取り名人。"),
                    speed: 0.035, zone: .bottom, lifespanDays: 250, design: fishDesign {
                        $0.length = 11; $0.aspect = 0.4; $0.depth = 0.6
                        $0.back = 0x6A6040; $0.body = 0xB8B090; $0.bellyColor = 0xE8E0C8; $0.fin = 0xC0B8A0
                        $0.patterns = [.hBand(y: 0, thickness: 0.28, color: 0x303020)]
                    }),
        FishSpecies(id: "loach", name: String(localized: "クーリーローチ"), price: 65, blurb: String(localized: "しましまのにょろにょろ。"),
                    speed: 0.04, zone: .bottom, lifespanDays: 400, design: fishDesign {
                        $0.length = 20; $0.aspect = 0.25; $0.tail = .pointed; $0.tailFrac = 0.1; $0.depth = 0.7; $0.peduncle = 0.8
                        $0.blunt = 0.7; $0.dorsal = .none; $0.anal = .none; $0.barbels = true; $0.pectoral = false
                        $0.back = 0x3A2A1A; $0.body = 0xF0A040; $0.bellyColor = 0xF8D090; $0.fin = 0xE09040
                        $0.patterns = [.vStripes(count: 8, width: 0.06, color: 0x2A1A10, from: 0.04, to: 0.94)]
                    }),
        FishSpecies(id: "pleco", name: String(localized: "セルフィンプレコ"), price: 150, blurb: String(localized: "大きな背びれの底の主。"),
                    speed: 0.03, zone: .bottom, lifespanDays: 365, design: fishDesign {
                        $0.length = 20; $0.aspect = 0.36; $0.tailFrac = 0.18; $0.dorsal = .sail; $0.dorsalHeight = 0.6; $0.depth = 0.66; $0.belly = 0.6
                        $0.back = 0x3A3024; $0.body = 0x5A4A38; $0.bellyColor = 0x7A6A54; $0.fin = 0x4A3C2C; $0.barbels = true
                        $0.patterns = [.spots(count: 16, size: 0.025, color: 0xE0D0A0)]
                    }),
        // MARK: 金魚・コイ
        FishSpecies(id: "goldfish", name: String(localized: "金魚"), price: 80, blurb: String(localized: "ぽってりした定番の人気者。"),
                    speed: 0.05, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 15; $0.aspect = 0.6; $0.tail = .double; $0.tailFrac = 0.32; $0.tailSpread = 0.9; $0.depth = 0.72
                        $0.blunt = 0.8; $0.belly = 1.1
                        $0.back = 0xE8600C; $0.body = 0xFF8C1A; $0.bellyColor = 0xFFC860; $0.fin = 0xFFA050
                    }),
        FishSpecies(id: "ryukin", name: String(localized: "琉金"), price: 110, blurb: String(localized: "紅白の丸い体と長い尾。"),
                    speed: 0.045, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 16; $0.aspect = 0.8; $0.tail = .double; $0.tailFrac = 0.36; $0.tailSpread = 1.0; $0.depth = 0.82; $0.hump = 0.4
                        $0.blunt = 0.85; $0.back = 0xD02010; $0.body = 0xFF4020; $0.bellyColor = 0xFFA080; $0.fin = 0xFF6040
                        $0.patterns = [.patches(count: 3, color: 0xFFF4EC)]
                    }),
        FishSpecies(id: "demekin", name: String(localized: "黒出目金"), price: 120, blurb: String(localized: "飛び出た目がチャームポイント。"),
                    speed: 0.04, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 15; $0.aspect = 0.72; $0.tail = .double; $0.tailFrac = 0.34; $0.tailSpread = 0.95; $0.depth = 0.75; $0.blunt = 0.85
                        $0.bulgingEyes = true; $0.eyeSize = 1.9
                        $0.back = 0x101014; $0.body = 0x24242C; $0.bellyColor = 0x34343E; $0.fin = 0x1A1A22; $0.iris = 0xB08030
                    }),
        FishSpecies(id: "koi", name: String(localized: "錦鯉"), price: 400, blurb: String(localized: "紅白の模様が美しい池の王様。"),
                    speed: 0.04, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 26; $0.aspect = 0.36; $0.depth = 0.72; $0.blunt = 0.6; $0.barbels = true
                        $0.back = 0xF4F0EA; $0.body = 0xFFFFFF; $0.bellyColor = 0xFFFFFF; $0.fin = 0xF4F0EA
                        $0.patterns = [.patches(count: 4, color: 0xE02010), .patches(count: 1, color: 0x151515)]
                    }),
        // MARK: 熱帯の中型魚
        FishSpecies(id: "betta", name: String(localized: "ベタ"), price: 120, blurb: String(localized: "ドレスのようなひれを持つ。"),
                    speed: 0.04, zone: .upper, lifespanDays: 150, design: fishDesign {
                        $0.length = 15; $0.aspect = 0.7; $0.tail = .veil; $0.tailFrac = 0.38; $0.tailSpread = 1.0; $0.dorsal = .sail
                        $0.dorsalHeight = 0.6; $0.anal = .veil; $0.analHeight = 0.7; $0.depth = 0.45
                        $0.back = 0x8A0C3A; $0.body = 0xC8185A; $0.bellyColor = 0xE04A80; $0.fin = 0x7B2AB0
                    }),
        FishSpecies(id: "angel", name: String(localized: "エンゼルフィッシュ"), price: 150, blurb: String(localized: "縦長の体でゆったり泳ぐ。"),
                    speed: 0.045, zone: .any, lifespanDays: 300, design: fishDesign {
                        $0.length = 13; $0.aspect = 1.3; $0.tailFrac = 0.2; $0.depth = 0.45; $0.dorsal = .tall; $0.dorsalHeight = 0.9
                        $0.anal = .tall; $0.analHeight = 0.9; $0.filaments = true
                        $0.back = 0xC0C0B0; $0.body = 0xE8E8D8; $0.bellyColor = 0xF4F4EA; $0.fin = 0xD8D8C8
                        $0.patterns = [.vStripes(count: 3, width: 0.08, color: 0x303030, from: 0.15, to: 0.75)]
                    }),
        FishSpecies(id: "discus", name: String(localized: "ディスカス"), price: 500, blurb: String(localized: "熱帯魚の王様と呼ばれる円盤形。"),
                    speed: 0.035, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 17; $0.aspect = 0.95; $0.tail = .round; $0.tailFrac = 0.15; $0.depth = 0.86; $0.blunt = 0.9
                        $0.dorsal = .long; $0.dorsalHeight = 0.4; $0.anal = .long; $0.analHeight = 0.36
                        $0.back = 0xA03020; $0.body = 0xE06030; $0.bellyColor = 0xF09040; $0.fin = 0xD05028; $0.iris = 0xD02020
                        $0.patterns = [.hBand(y: -0.5, thickness: 0.12, color: 0x3AA0C8), .hBand(y: 0.0, thickness: 0.12, color: 0x3AA0C8),
                                       .hBand(y: 0.5, thickness: 0.12, color: 0x3AA0C8)]
                    }),
        FishSpecies(id: "arowana", name: String(localized: "シルバーアロワナ"), price: 800, blurb: String(localized: "銀色にかがやく古代魚。"),
                    speed: 0.05, zone: .upper, lifespanDays: 365, design: fishDesign {
                        $0.length = 32; $0.aspect = 0.3; $0.tail = .round; $0.tailFrac = 0.14; $0.depth = 0.7; $0.blunt = 0.3; $0.hump = 0.55
                        $0.dorsal = .long; $0.dorsalHeight = 0.3; $0.anal = .long; $0.analHeight = 0.35; $0.barbels = true
                        $0.back = 0x405040; $0.body = 0xC0C8B0; $0.bellyColor = 0xE8ECD8; $0.fin = 0xA0A890
                    }),
        // MARK: 海の魚
        FishSpecies(id: "clown", name: String(localized: "カクレクマノミ"), price: 180, blurb: String(localized: "オレンジと白のしま模様。"),
                    speed: 0.06, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 14; $0.aspect = 0.5; $0.tail = .round; $0.tailFrac = 0.2; $0.depth = 0.62; $0.blunt = 0.75
                        $0.back = 0xE8600C; $0.body = 0xFF7B1C; $0.bellyColor = 0xFF9A4C; $0.fin = 0xFF8A30
                        $0.patterns = [.vStripes(count: 3, width: 0.12, color: 0xFFFFFF, edge: 0x1A1A1A, from: 0.12, to: 0.85)]
                    }),
        FishSpecies(id: "damsel", name: String(localized: "ルリスズメダイ"), price: 60, blurb: String(localized: "目のさめるような瑠璃色。"),
                    speed: 0.09, zone: .any, lifespanDays: 300, design: fishDesign {
                        $0.length = 12; $0.aspect = 0.5; $0.depth = 0.66
                        $0.back = 0x1040C0; $0.body = 0x2070FF; $0.bellyColor = 0x60A0FF; $0.fin = 0x3080FF
                    }),
        FishSpecies(id: "bluetang", name: String(localized: "ナンヨウハギ"), price: 260, blurb: String(localized: "青い体に黒いもよう。"),
                    speed: 0.06, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 16; $0.aspect = 0.62; $0.tail = .crescent; $0.depth = 0.8; $0.blunt = 0.7; $0.dorsal = .long; $0.anal = .long
                        $0.back = 0x103090; $0.body = 0x2050D0; $0.bellyColor = 0x3070E0; $0.fin = 0xF0D020
                        $0.patterns = [.hBand(y: -0.3, thickness: 0.3, color: 0x101030, from: 0.15, to: 0.85)]
                    }),
        FishSpecies(id: "yellowtang", name: String(localized: "キイロハギ"), price: 240, blurb: String(localized: "あざやかな黄色い円盤。"),
                    speed: 0.06, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 15; $0.aspect = 0.8; $0.tail = .crescent; $0.depth = 0.86; $0.blunt = 0.6
                        $0.dorsal = .long; $0.dorsalHeight = 0.5; $0.anal = .long; $0.analHeight = 0.45
                        $0.back = 0xE0C000; $0.body = 0xF0D010; $0.bellyColor = 0xFFF060; $0.fin = 0xF8DC20
                    }),
        FishSpecies(id: "butterfly", name: String(localized: "チョウチョウウオ"), price: 200, blurb: String(localized: "尾の近くに目玉もよう。"),
                    speed: 0.055, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 14; $0.aspect = 0.95; $0.tail = .round; $0.tailFrac = 0.14; $0.depth = 0.85; $0.blunt = 0.55
                        $0.dorsal = .long; $0.anal = .long
                        $0.back = 0xE8E0C0; $0.body = 0xF8F0D8; $0.bellyColor = 0xFFFFF0; $0.fin = 0xF0D040
                        $0.patterns = [.rear(color: 0xF0D040, from: 0.35), .vStripes(count: 1, width: 0.08, color: 0x202020, from: 0.86, to: 0.86),
                                       .eyeSpot(color: 0x202020)]
                    }),
        FishSpecies(id: "gramma", name: String(localized: "ロイヤルグラマ"), price: 170, blurb: String(localized: "紫と黄色のツートン。"),
                    speed: 0.06, zone: .any, lifespanDays: 300, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.45; $0.tail = .round; $0.depth = 0.64
                        $0.back = 0x7020A0; $0.body = 0x9030C0; $0.bellyColor = 0xB060D8; $0.fin = 0xC080E0
                        $0.patterns = [.rear(color: 0xF8D020, from: 0.45)]
                    }),
        FishSpecies(id: "mandarin", name: String(localized: "ニシキテグリ"), price: 350, blurb: String(localized: "サイケデリックな模様の人気者。"),
                    speed: 0.035, zone: .bottom, lifespanDays: 300, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.55; $0.tail = .round; $0.dorsal = .sail; $0.dorsalHeight = 0.5; $0.depth = 0.64; $0.blunt = 0.8
                        $0.back = 0x1060A0; $0.body = 0x2080C0; $0.bellyColor = 0x30A0D0; $0.fin = 0xFF8020
                        $0.patterns = [.patches(count: 5, color: 0xFF8020), .spots(count: 6, size: 0.04, color: 0x20D0C0)]
                    }),
        FishSpecies(id: "lionfish", name: String(localized: "ハナミノカサゴ"), price: 450, blurb: String(localized: "とげとげのひれが華やか。"),
                    speed: 0.03, zone: .any, lifespanDays: 365, design: fishDesign {
                        $0.length = 18; $0.aspect = 0.9; $0.tail = .round; $0.dorsal = .spiky; $0.dorsalHeight = 0.9; $0.depth = 0.5
                        $0.back = 0xB03020; $0.body = 0xF0E0D0; $0.bellyColor = 0xFFF4EC; $0.fin = 0xF0C0B0
                        $0.patterns = [.vStripes(count: 7, width: 0.06, color: 0xC03020, from: 0.02, to: 0.95)]
                    }),
        FishSpecies(id: "puffer", name: String(localized: "ミドリフグ"), price: 220, blurb: String(localized: "まんまるで好奇心旺盛。"),
                    speed: 0.035, zone: .any, lifespanDays: 240, design: fishDesign {
                        $0.length = 13; $0.aspect = 0.62; $0.tail = .round; $0.tailFrac = 0.18; $0.depth = 0.82; $0.blunt = 0.9; $0.belly = 1.1
                        $0.back = 0x5A9A30; $0.body = 0x7CC242; $0.bellyColor = 0xF4F0C0; $0.fin = 0x9CD262
                        $0.patterns = [.spots(count: 6, size: 0.05, color: 0x1E3A12)]
                    }),
    ]

    private static func deco(_ id: String, _ name: String, _ price: Int, _ blurb: String, _ category: DecorationCategory,
                             _ w: CGFloat, _ h: CGFloat, bubbles: Double = 0, _ design: DecoDesign) -> DecorationKind {
        DecorationKind(id: id, name: name, price: price, blurb: blurb, bubbles: bubbles, size: CGSize(width: w, height: h), design: design, category: category)
    }

    static let decorations: [DecorationKind] = [
        // MARK: 水草
        deco("grass", String(localized: "水草"), 15, String(localized: "ゆれる緑の水草。"), .plant, 14, 20, .grass(color: 0x3FAE4A, blades: 6, height: 1)),
        deco("redgrass", String(localized: "赤い水草"), 40, String(localized: "水槽のアクセントになる赤。"), .plant, 14, 24, .grass(color: 0xC84038, blades: 6, height: 1)),
        deco("tallgrass", String(localized: "バリスネリア"), 30, String(localized: "水面近くまで伸びるリボン状の葉。"), .plant, 12, 46, .ribbon(color: 0x5BC96A, blades: 4)),
        deco("sword", String(localized: "アマゾンソード"), 45, String(localized: "大きな葉が広がる定番水草。"), .plant, 28, 34, .sword(color: 0x2E8B3A)),
        deco("fern", String(localized: "ミクロソリウム"), 35, String(localized: "しだのような葉が茂る。"), .plant, 22, 28, .fern(color: 0x3C9A44)),
        deco("marimo", String(localized: "マリモ"), 25, String(localized: "ころんと丸い緑の玉。"), .plant, 9, 9, .ball(color: 0x3E8A3A)),
        deco("lotus", String(localized: "スイレン"), 60, String(localized: "ピンクの花が咲く。"), .plant, 22, 34, .lotus(leaf: 0x3FA050, flower: 0xF4A0C0)),
        // MARK: 石・流木
        deco("rock", String(localized: "岩"), 20, String(localized: "どっしりした石。"), .stone, 28, 16, .rock(color: 0x8A8F99, lumps: 2)),
        deco("bluerock", String(localized: "青い石"), 30, String(localized: "青みがかった美しい石。"), .stone, 20, 14, .rock(color: 0x5A7494, lumps: 4)),
        deco("lava", String(localized: "溶岩石"), 35, String(localized: "ごつごつした黒い石。"), .stone, 22, 13, .rock(color: 0x5A3A36, lumps: 6)),
        deco("pebbles", String(localized: "玉砂利"), 15, String(localized: "色とりどりの小石。"), .stone, 24, 8, .pebbles(colors: [0xE8E0D0, 0xB0A898, 0x8A9098, 0xD8C0A0])),
        deco("stack", String(localized: "石積み"), 50, String(localized: "バランスよく積んだ石。"), .stone, 18, 24, .stack(color: 0x8A8478)),
        deco("wood", String(localized: "流木"), 40, String(localized: "自然な雰囲気の流木。"), .stone, 48, 16, .wood(color: 0x8D6E4C)),
        deco("arch", String(localized: "岩のアーチ"), 120, String(localized: "魚がくぐれる岩の門。"), .stone, 44, 30,
             .parts([.p([(0, 1), (0.02, 0.45), (0.12, 0.12), (0.5, 0), (0.88, 0.12), (0.98, 0.45), (1, 1), (0.74, 1), (0.7, 0.55),
                         (0.6, 0.38), (0.5, 0.34), (0.4, 0.38), (0.3, 0.55), (0.26, 1)], 0x7A7C84, texture: .stone)])),
        // MARK: サンゴ・貝
        deco("coral", String(localized: "サンゴ"), 50, String(localized: "ピンクの枝サンゴ。"), .sea, 16, 18, .branchCoral(color: 0xFF7F9E)),
        deco("fancoral", String(localized: "ウミウチワ"), 80, String(localized: "扇のように広がるサンゴ。"), .sea, 26, 28, .fanCoral(color: 0xE85A3A)),
        deco("braincoral", String(localized: "ノウサンゴ"), 70, String(localized: "しわしわのドーム形。"), .sea, 22, 11, .brainCoral(color: 0xC8B060)),
        deco("tubecoral", String(localized: "チューブサンゴ"), 60, String(localized: "筒が集まったサンゴ。"), .sea, 20, 16, .tubeCoral(color: 0xF08A30, tip: 0xFFE070)),
        deco("anemone", String(localized: "イソギンチャク"), 90, String(localized: "クマノミの大好きなおうち。"), .sea, 20, 20, .anemone(color: 0xB05A90, tip: 0xF0C0E0)),
        deco("shell", String(localized: "貝がら"), 10, String(localized: "砂の上の小さなアクセント。"), .sea, 9, 7, .scallop(color: 0xFFC9D6)),
        deco("conch", String(localized: "巻き貝"), 15, String(localized: "くるりと巻いた貝。"), .sea, 10, 7, .conch(color: 0xF0D8B0)),
        deco("starfish", String(localized: "ヒトデ"), 20, String(localized: "砂の上のお星さま。"), .sea, 10, 9, .starfish(color: 0xF08040)),
        // MARK: 置きもの
        deco("airstone", String(localized: "エアストーン"), 60, String(localized: "ぷくぷく泡が出る。"), .structure, 8, 4, bubbles: 0.9,
             .parts([.r(0.05, 0.25, 0.9, 0.75, 0x8A9098, radius: 0.2, texture: .stone)])),
        deco("chest", String(localized: "宝箱"), 90, String(localized: "ときどき泡が出る宝箱。"), .structure, 26, 18, bubbles: 0.15,
             .parts([.r(0, 0.4, 1, 0.6, 0x9B6A3B, texture: .wood), .r(0, 0.05, 1, 0.38, 0x8A5A2E, radius: 0.25, texture: .wood),
                     .r(0.14, 0.05, 0.08, 0.95, 0xD4A93A, role: .detail), .r(0.78, 0.05, 0.08, 0.95, 0xD4A93A, role: .detail),
                     .r(0.43, 0.36, 0.14, 0.2, 0xFFD54F, role: .detail)])),
        deco("pot", String(localized: "つぼ"), 45, String(localized: "古代の沈んだつぼ。"), .structure, 12, 18,
             .parts([.p([(0.32, 0), (0.68, 0), (0.64, 0.14), (0.95, 0.5), (0.76, 1), (0.24, 1), (0.05, 0.5), (0.36, 0.14)], 0xC06A3A, smooth: true),
                     .e(0.3, 0, 0.4, 0.08, 0x2A1810, role: .dark), .r(0.12, 0.46, 0.76, 0.06, 0x8A3A1A, role: .detail)])),
        deco("anchor", String(localized: "いかり"), 70, String(localized: "沈んだ船のいかり。"), .structure, 18, 22,
             .parts([.r(0.44, 0.12, 0.12, 0.8, 0x5A6068, texture: .metal), .e(0.36, 0, 0.28, 0.16, 0x5A6068),
                     .r(0.2, 0.2, 0.6, 0.07, 0x5A6068), .p([(0, 0.58), (0.1, 0.54), (0.5, 0.9), (0.9, 0.54), (1, 0.58), (0.5, 1)], 0x5A6068)])),
        deco("diver", String(localized: "潜水ヘルメット"), 120, String(localized: "泡を吐く昔の潜水服。"), .structure, 16, 18, bubbles: 0.4,
             .parts([.e(0.08, 0, 0.84, 0.86, 0xC8903A, texture: .metal), .e(0.3, 0.22, 0.4, 0.38, 0x203040, role: .dark),
                     .r(0.02, 0.74, 0.96, 0.26, 0x9A6A2A, radius: 0.08)])),
        deco("gems", String(localized: "光る宝石"), 250, String(localized: "ほんのり光るクリスタル。"), .structure, 16, 10,
             .parts([.e(0, 0.75, 1, 0.25, 0x6A6070, texture: .stone), .p([(0.1, 0.95), (0.22, 0.25), (0.36, 0.95)], 0x40E0FF, role: .glow),
                     .p([(0.32, 0.95), (0.47, 0), (0.62, 0.95)], 0xFF60D0, role: .glow), .p([(0.58, 0.95), (0.72, 0.4), (0.86, 0.95)], 0x70FF90, role: .glow)])),
        deco("torii", String(localized: "鳥居"), 180, String(localized: "水の中の小さな神社。"), .structure, 30, 30,
             .parts([.r(0.16, 0.18, 0.1, 0.82, 0xD83A2A), .r(0.74, 0.18, 0.1, 0.82, 0xD83A2A), .r(0.08, 0.3, 0.84, 0.07, 0xD83A2A),
                     .p([(0, 0.04), (1, 0.04), (0.94, 0.17), (0.06, 0.17)], 0x2A2424)])),
        deco("pillars", String(localized: "遺跡の柱"), 160, String(localized: "海に沈んだ古代の神殿。"), .structure, 36, 28,
             .parts([.r(0.05, 0.2, 0.17, 0.8, 0xD8D0C0, texture: .stone), .r(0.4, 0.36, 0.17, 0.64, 0xD8D0C0, texture: .stone),
                     .r(0.78, 0.56, 0.16, 0.44, 0xD0C8B8, texture: .stone), .r(0, 0.14, 0.27, 0.07, 0xE0D8C8), .r(0.35, 0.3, 0.27, 0.07, 0xE0D8C8),
                     .r(0.55, 0.86, 0.26, 0.14, 0xC8C0B0, radius: 0.07, texture: .stone)])),
        deco("pineapple", String(localized: "パイナップルの家"), 220, String(localized: "海の底のかわいいおうち。"), .structure, 22, 32,
             .parts([.p([(0.5, 0.32), (0.25, 0), (0.42, 0.2), (0.5, 0), (0.58, 0.2), (0.75, 0), (0.5, 0.32)], 0x3A9A3A),
                     .e(0.08, 0.24, 0.84, 0.76, 0xF0B030, texture: .wood), .a(0.38, 0.62, 0.24, 0.38, 0x3A78C0, role: .detail),
                     .e(0.2, 0.42, 0.18, 0.14, 0x2A3A50, role: .dark), .e(0.62, 0.42, 0.18, 0.14, 0x2A3A50, role: .dark)])),
        deco("lighthouse", String(localized: "灯台"), 200, String(localized: "てっぺんが光る灯台。"), .structure, 16, 44,
             .parts([.p([(0.22, 1), (0.78, 1), (0.64, 0.26), (0.36, 0.26)], 0xF0F0F0), .r(0.3, 0.44, 0.4, 0.09, 0xD03030, role: .detail),
                     .r(0.26, 0.7, 0.48, 0.09, 0xD03030, role: .detail), .r(0.34, 0.13, 0.32, 0.13, 0xFFE070, role: .glow),
                     .p([(0.28, 0.13), (0.72, 0.13), (0.5, 0)], 0xD03030), .a(0.43, 0.84, 0.14, 0.16)])),
        deco("castle", String(localized: "お城"), 150, String(localized: "水槽の主役になるお城。"), .structure, 50, 40,
             .parts([.r(0, 0.22, 0.24, 0.78, 0xC0B8A8, texture: .stone), .r(0.76, 0.22, 0.24, 0.78, 0xC0B8A8, texture: .stone),
                     .r(0.2, 0.42, 0.6, 0.58, 0xB8B0A0, texture: .stone),
                     .p([(0, 0.22), (0.12, 0), (0.24, 0.22)], 0xB04040), .p([(0.76, 0.22), (0.88, 0), (1, 0.22)], 0xB04040),
                     .r(0.22, 0.36, 0.08, 0.07, 0xB8B0A0), .r(0.38, 0.36, 0.08, 0.07, 0xB8B0A0), .r(0.54, 0.36, 0.08, 0.07, 0xB8B0A0),
                     .r(0.7, 0.36, 0.08, 0.07, 0xB8B0A0), .a(0.07, 0.35, 0.1, 0.16), .a(0.83, 0.35, 0.1, 0.16), .a(0.41, 0.62, 0.18, 0.38)])),
        deco("ship", String(localized: "沈没船"), 300, String(localized: "かつて海をわたった大きな船。"), .structure, 70, 32, bubbles: 0.1,
             .parts([.p([(0.06, 0.28), (0.2, 0.08), (0.24, 0.1), (0.13, 0.4)], 0xD8D0B8, role: .fin),
                     .r(0.22, 0.02, 0.025, 0.5, 0x5A3A20, texture: .wood), .p([(0.55, 0.3), (0.6, 0.0), (0.62, 0.0), (0.58, 0.35)], 0x5A3A20),
                     .p([(0, 0.48), (1, 0.34), (0.9, 1), (0.1, 1)], 0x6A4A30, texture: .wood), .r(0.02, 0.44, 0.96, 0.05, 0x4A3020, role: .detail),
                     .e(0.25, 0.6, 0.06, 0.12, 0x1C1410, role: .dark), .e(0.45, 0.58, 0.06, 0.12, 0x1C1410, role: .dark),
                     .e(0.65, 0.56, 0.06, 0.12, 0x1C1410, role: .dark), .p([(0.75, 0.4), (0.85, 0.5), (0.8, 0.75), (0.72, 0.6)], 0x1C1410, role: .dark)])),
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
        TankSize(level: 0, name: String(localized: "小さな水槽"), maxFish: 8, maxDecorations: 10, price: 0),
        TankSize(level: 1, name: String(localized: "ふつうの水槽"), maxFish: 14, maxDecorations: 18, price: 300),
        TankSize(level: 2, name: String(localized: "大きな水槽"), maxFish: 22, maxDecorations: 26, price: 800),
        TankSize(level: 3, name: String(localized: "特大の水槽"), maxFish: 32, maxDecorations: 36, price: 1500),
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

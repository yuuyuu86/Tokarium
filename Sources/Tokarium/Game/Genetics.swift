import Foundation

// MARK: - 品種（色の遺伝）

/// 色の遺伝子。魚は2つずつ持ち、親から1つずつ受け継ぐ。
/// 野生型（wild）は優性で、ほかの色は2つそろうか、特別な組み合わせのときだけ表に出る。
enum ColorGene: String, Codable, CaseIterable {
    case wild, albino, black, gold, blue, red, pastel

    var label: String {
        switch self {
        case .wild: return String(localized: "野生型")
        case .albino: return String(localized: "アルビノ")
        case .black: return String(localized: "ブラック")
        case .gold: return String(localized: "ゴールド")
        case .blue: return String(localized: "ブルー")
        case .red: return String(localized: "レッド")
        case .pastel: return String(localized: "パステル")
        }
    }

    /// 突然変異で生まれうる色。
    static let mutations: [ColorGene] = [.albino, .black, .gold, .blue, .red, .pastel]
}

/// 見た目の品種。遺伝子の組み合わせで決まる。
enum FishVariant: String, Codable, CaseIterable, Identifiable {
    case wild, albino, black, gold, blue, red, pastel
    // 2つの色の組み合わせで生まれる品種
    case sunset, sky, panda, purple, platinum, sakura
    var id: String { rawValue }

    var label: String {
        switch self {
        case .wild: return String(localized: "原種")
        case .albino: return String(localized: "アルビノ")
        case .black: return String(localized: "ブラック")
        case .gold: return String(localized: "ゴールド")
        case .blue: return String(localized: "ブルー")
        case .red: return String(localized: "レッド")
        case .pastel: return String(localized: "パステル")
        case .sunset: return String(localized: "サンセット")
        case .sky: return String(localized: "スカイ")
        case .panda: return String(localized: "パンダ")
        case .purple: return String(localized: "パープル")
        case .platinum: return String(localized: "プラチナ")
        case .sakura: return String(localized: "サクラ")
        }
    }

    /// 組み合わせで生まれる品種のレシピ（図鑑のヒントに使う）。
    static let recipes: [(Set<ColorGene>, FishVariant)] = [
        ([.gold, .red], .sunset),
        ([.blue, .pastel], .sky),
        ([.black, .albino], .panda),
        ([.blue, .red], .purple),
        ([.gold, .albino], .platinum),
        ([.red, .pastel], .sakura),
    ]

    /// 組み合わせの品種か。
    var isCombination: Bool { FishVariant.recipes.contains { $0.1 == self } }

    /// 組み合わせの品種のヒント（どの色を合わせるか）。
    var recipeHint: String? {
        guard let genes = FishVariant.recipes.first(where: { $0.1 == self })?.0 else { return nil }
        let names = genes.sorted { $0.rawValue < $1.rawValue }.map(\.label)
        return String(localized: "\(names[0])と\(names[1])の遺伝子を1つずつ")
    }
}

/// 魚の遺伝子の組（2つ）。
struct Genotype: Codable, Equatable, Hashable {
    var a: ColorGene = .wild
    var b: ColorGene = .wild

    static let wild = Genotype()

    var genes: [ColorGene] { [a, b] }

    /// 見た目に出る品種。
    var variant: FishVariant {
        if a == b { return FishVariant(rawValue: a.rawValue) ?? .wild }
        if a == .wild || b == .wild { return .wild }
        let pair: Set<ColorGene> = [a, b]
        if let hit = FishVariant.recipes.first(where: { $0.0 == pair }) { return hit.1 }
        // 組み合わせのない2色は、強い方の色が出る
        let order: [ColorGene] = [.black, .red, .blue, .gold, .pastel, .albino]
        let strong = order.first { pair.contains($0) } ?? .wild
        return FishVariant(rawValue: strong.rawValue) ?? .wild
    }

    /// 見た目には出ていない（かくれている）遺伝子。
    var hiddenGenes: [ColorGene] {
        let v = variant
        return genes.filter { g in g != .wild && v.rawValue != g.rawValue && !v.isCombination }
    }

    /// 遺伝子の説明（例: 「野生型 × ゴールド」）。
    var text: String { "\(a.label) × \(b.label)" }

    /// お店の魚の遺伝子。たいていは野生型で、ときどき色の遺伝子をかくし持っている。
    /// かくし持つ色は、種類ごとの「出やすい色」になりやすい（同じ色の2匹を見つけやすいように）。
    static func forShop<R: RandomNumberGenerator>(speciesID: String, rng: inout R) -> Genotype {
        guard Double.random(in: 0..<1, using: &rng) < Genetics.shopCarrierChance else { return .wild }
        let pool = Double.random(in: 0..<1, using: &rng) < Genetics.paletteChance ? Genetics.palette(speciesID) : ColorGene.mutations
        return Genotype(a: .wild, b: pool.randomElement(using: &rng) ?? .gold)
    }
}

// MARK: - 性格

/// 魚の性格。泳ぎ方や、たたいたときの寄ってき方が変わる。
enum Personality: String, Codable, CaseIterable {
    case glutton, friendly, shy, active, calm, curious

    var label: String {
        switch self {
        case .glutton: return String(localized: "くいしんぼう")
        case .friendly: return String(localized: "人なつこい")
        case .shy: return String(localized: "臆病")
        case .active: return String(localized: "元気")
        case .calm: return String(localized: "のんびり")
        case .curious: return String(localized: "好奇心旺盛")
        }
    }

    var blurb: String {
        switch self {
        case .glutton: return String(localized: "餌にまっさきに飛びつく。おなかがすくのも少し早い。")
        case .friendly: return String(localized: "水をたたくと、すぐに寄ってくる。なつきやすい。")
        case .shy: return String(localized: "水をたたくと逃げてしまう。なつくと寄ってくるように。")
        case .active: return String(localized: "いつも元気に泳ぎまわる。")
        case .calm: return String(localized: "ゆったりと泳ぐ。")
        case .curious: return String(localized: "装飾のまわりをよく見に行く。")
        }
    }

    /// 泳ぐ速さにかける数。
    var speedFactor: Double {
        switch self {
        case .active: return 1.3
        case .calm: return 0.75
        default: return 1
        }
    }

    /// なつき度の上がりやすさ。
    var affectionFactor: Double {
        switch self {
        case .friendly: return 1.5
        case .shy: return 0.7
        default: return 1
        }
    }
}

// MARK: - 遺伝のルール

enum Genetics {
    /// お店の魚が色の遺伝子をかくし持っている確率。
    static let shopCarrierChance = 0.5
    /// かくし持つ色が、その種類の出やすい色である確率。
    static let paletteChance = 0.75

    /// 種類ごとの出やすい色（2つ。種類で決まっていて変わらない）。
    static func palette(_ speciesID: String) -> [ColorGene] {
        var rng = SeededRandom(seed: ("palette-" + speciesID).stableSeed)
        return Array(ColorGene.mutations.shuffled(using: &rng).prefix(2))
    }
    /// 生まれるとき、遺伝子1つが突然変異する確率。
    static let mutationChance = 0.04
    /// 稚魚が親のどちらかの性格を受け継ぐ確率。
    static let inheritPersonalityChance = 0.5

    /// 両親から1つずつ遺伝子を受け継ぐ（まれに突然変異）。
    static func child<R: RandomNumberGenerator>(of p1: Genotype, _ p2: Genotype, rng: inout R) -> Genotype {
        var a = Bool.random(using: &rng) ? p1.a : p1.b
        var b = Bool.random(using: &rng) ? p2.a : p2.b
        if Double.random(in: 0..<1, using: &rng) < mutationChance { a = ColorGene.mutations.randomElement(using: &rng) ?? a }
        if Double.random(in: 0..<1, using: &rng) < mutationChance { b = ColorGene.mutations.randomElement(using: &rng) ?? b }
        return Genotype(a: a, b: b)
    }

    /// 稚魚の性格。
    static func childPersonality<R: RandomNumberGenerator>(_ p1: Personality, _ p2: Personality, rng: inout R) -> Personality {
        if Double.random(in: 0..<1, using: &rng) < inheritPersonalityChance { return Bool.random(using: &rng) ? p1 : p2 }
        return Personality.allCases.randomElement(using: &rng) ?? .calm
    }

    /// 稚魚の体の大きさ（両親の平均に少しゆらぎ）。
    static func childSize<R: RandomNumberGenerator>(_ s1: Double, _ s2: Double, rng: inout R) -> Double {
        min(Fish.sizeRange.upperBound, max(Fish.sizeRange.lowerBound, (s1 + s2) / 2 * Double.random(in: 0.95...1.08, using: &rng)))
    }

    /// この2匹から生まれうる品種と、その確率（突然変異は含まない）。
    static func outcomes(_ p1: Genotype, _ p2: Genotype) -> [(FishVariant, Double)] {
        var result: [FishVariant: Double] = [:]
        for a in p1.genes {
            for b in p2.genes {
                result[Genotype(a: a, b: b).variant, default: 0] += 0.25
            }
        }
        return result.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: - なつき度

enum Affection {
    static let max = 100.0
    /// 1匹に餌をあげたとき。
    static let perFeedOne = 4.0
    /// みんなに餌をあげたとき。
    static let perFeedAll = 1.0
    /// 近くの水をたたいたとき（1分に1回まで）。
    static let perTouch = 1.0
    static let touchInterval: TimeInterval = 60
    static let perMedicine = 5.0

    /// ハートの数（0〜5）。
    static func hearts(_ value: Double) -> Int { Int((value / 20).rounded(.down)).clamped(0, 5) }
}

extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(hi, Swift.max(lo, self)) }
}

// MARK: - 今日の入荷

/// お店に毎日2匹並ぶ、品種の魚（単色の品種だけ。組み合わせの品種は繁殖でしか手に入らない）。
struct StockOffer: Identifiable, Equatable {
    let id: String
    let speciesID: String
    let variant: FishVariant

    var species: FishSpecies { Catalog.species(speciesID) }
    var price: Int { species.price * 3 + 60 }
    var name: String { String(localized: "\(variant.label)・\(species.name)") }
}

enum DailyStock {
    static let count = 2

    /// その日の入荷。ランクで買える種類の中から、日付で決まった魚が並ぶ。
    static func offers(on date: Date = Date(), rank: Int) -> [StockOffer] {
        let day = DayKey.key(date)
        var rng = SeededRandom(seed: ("stock-" + day).stableSeed)
        let candidates = Catalog.fish.filter { $0.isRegular && KeeperRank.required($0) <= rank }
        return candidates.shuffled(using: &rng).prefix(count).enumerated().map { i, sp in
            let colors = Genetics.palette(sp.id)
            let gene = colors[Int.random(in: 0..<colors.count, using: &rng)]
            return StockOffer(id: "\(day):\(i)", speciesID: sp.id, variant: FishVariant(rawValue: gene.rawValue) ?? .gold)
        }
    }
}

import Foundation

// MARK: - レイアウトの評価

/// 置いた装飾の組み合わせや並べ方に点数をつける（100点満点）。
struct LayoutScore: Equatable {
    struct Part: Equatable {
        let title: String
        let points: Int
        let max: Int
    }

    struct Bonus: Equatable {
        let title: String
        let detail: String
        let points: Int
    }

    var parts: [Part] = []
    var bonuses: [Bonus] = []
    var tips: [String] = []

    var total: Int { min(100, parts.reduce(0) { $0 + $1.points } + bonuses.reduce(0) { $0 + $1.points }) }

    /// 星の数（0〜5）。
    var stars: Int { (total / 20).clamped(0, 5) }

    var rankText: String {
        switch total {
        case 90...: return String(localized: "すばらしい")
        case 70..<90: return String(localized: "とてもよい")
        case 50..<70: return String(localized: "よい")
        case 30..<50: return String(localized: "まずまず")
        default: return String(localized: "これから")
        }
    }
}

/// 組み合わせのボーナス。
struct LayoutCombo {
    let title: String
    let detail: String
    let points: Int
    let matches: ([Decoration]) -> Bool
}

enum Layout {
    static let combos: [LayoutCombo] = [
        LayoutCombo(title: String(localized: "水草の森"), detail: String(localized: "水草を4つ以上（2種類以上）"), points: 10) { d in
            let plants = d.filter { $0.kind.category == .plant }
            return plants.count >= 4 && Set(plants.map(\.kindID)).count >= 2
        },
        LayoutCombo(title: String(localized: "岩場"), detail: String(localized: "石・流木を3種類以上"), points: 10) { d in
            Set(d.filter { $0.kind.category == .stone }.map(\.kindID)).count >= 3
        },
        LayoutCombo(title: String(localized: "サンゴ礁"), detail: String(localized: "サンゴ・貝を3つ以上（サンゴを含む）"), points: 10) { d in
            let sea = d.filter { $0.kind.category == .sea }
            return sea.count >= 3 && sea.contains { $0.kindID.contains("coral") }
        },
        LayoutCombo(title: String(localized: "沈没船の宝"), detail: String(localized: "沈没船と宝箱"), points: 10) { d in
            has(d, "ship") && has(d, "chest")
        },
        LayoutCombo(title: String(localized: "和の庭"), detail: String(localized: "鳥居と、石積みかスイレン"), points: 10) { d in
            has(d, "torii") && (has(d, "stack") || has(d, "lotus"))
        },
        LayoutCombo(title: String(localized: "古代遺跡"), detail: String(localized: "遺跡の柱と、つぼか岩のアーチ"), points: 10) { d in
            has(d, "pillars") && (has(d, "pot") || has(d, "arch"))
        },
        LayoutCombo(title: String(localized: "海のおうち"), detail: String(localized: "パイナップルの家とイソギンチャク"), points: 8) { d in
            has(d, "pineapple") && has(d, "anemone")
        },
        LayoutCombo(title: String(localized: "夜の灯り"), detail: String(localized: "灯台か光る宝石と、水草"), points: 8) { d in
            (has(d, "lighthouse") || has(d, "gems")) && d.contains { $0.kind.category == .plant }
        },
    ]

    private static func has(_ d: [Decoration], _ id: String) -> Bool { d.contains { $0.kindID == id } }

    static func score(_ tank: Tank) -> LayoutScore {
        let placed = tank.decorations.filter(\.isPlaced)
        var s = LayoutScore()
        guard !placed.isEmpty else {
            s.tips.append(String(localized: "お店で装飾を買って置いてみましょう。"))
            return s
        }

        // 種類の多さ（4つの分類）
        let categories = Set(placed.map(\.kind.category))
        s.parts.append(.init(title: String(localized: "種類の多さ"), points: categories.count * 5, max: 20))
        if categories.count < 4 {
            let missing = DecorationCategory.allCases.filter { !categories.contains($0) }.map(\.label).joined(separator: String(localized: "、"))
            s.tips.append(String(localized: "\(missing)の装飾を足すと、種類の点が上がります。"))
        }

        // にぎやかさ（置ける数の半分〜9割がちょうどよい）
        let fill = Double(placed.count) / Double(max(1, tank.size.maxDecorations))
        let fullness: Int
        switch fill {
        case ..<0.2: fullness = 5
        case ..<0.5: fullness = 12
        case ...0.9: fullness = 20
        default: fullness = 15
        }
        s.parts.append(.init(title: String(localized: "にぎやかさ"), points: fullness, max: 20))
        if fill < 0.5 { s.tips.append(String(localized: "装飾をもう少し増やすと、にぎやかになります。")) }
        if fill > 0.9 { s.tips.append(String(localized: "少し減らして、魚の泳ぐ場所を空けると点が上がります。")) }

        // 広がり（左右5つの区画にどれだけ散らばっているか）
        let bins = Set(placed.map { min(4, Int($0.x * 5)) })
        s.parts.append(.init(title: String(localized: "広がり"), points: bins.count * 4, max: 20))
        if bins.count <= 2 && placed.count >= 3 { s.tips.append(String(localized: "装飾を左右に散らすと、広がりの点が上がります。")) }

        // 奥行き（奥と手前の両方を使う）
        let layers = Set(placed.map(\.layer)).count
        s.parts.append(.init(title: String(localized: "奥行き"), points: layers >= 2 ? 10 : 0, max: 10))
        if layers < 2 && placed.count >= 2 { s.tips.append(String(localized: "配置の編集で、右クリックから手前と奥を使い分けましょう。")) }

        for c in combos where c.matches(placed) {
            s.bonuses.append(.init(title: c.title, detail: c.detail, points: c.points))
        }
        if s.bonuses.isEmpty { s.tips.append(String(localized: "装飾の組み合わせでボーナスがもらえます。")) }
        return s
    }
}

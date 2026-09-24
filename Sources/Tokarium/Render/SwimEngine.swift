import Foundation

/// 泳ぎ・餌・泡など、保存しない見た目の動きを扱う。
/// 複数の画面（ウィンドウとデスクトップ）で同じ動きを共有する。
final class SwimEngine {
    struct Swimmer {
        var x: Double
        var y: Double
        var vx: Double = 0
        var vy: Double = 0
        var targetX: Double
        var targetY: Double
        var facingRight = true
        var retargetAt: Double = 0
        var phase: Double = .random(in: 0...10)
    }

    struct Pellet {
        var x: Double
        var y: Double
        var landedAt: Double?
    }

    struct Bubble {
        var x: Double
        var y: Double
        var speed: Double
        var wobble: Double
    }

    /// 砂の上端（正規化座標）。
    static let sandTop = 0.86

    private(set) var swimmers: [UUID: Swimmer] = [:]
    private(set) var pellets: [Pellet] = []
    private(set) var bubbles: [Bubble] = []
    private(set) var time: Double = 0
    private var lastDate: Date?
    private var bubbleClock: Double = 0

    /// 表示の縦横比（幅/高さ）。速度を画面比に合わせる。
    var aspect: Double = 16.0 / 10.0

    /// 餌を落とす。`near` を渡すとその横位置あたりに落とす。
    func dropFood(count: Int = 8, near x: Double? = nil) {
        let center = x ?? Double.random(in: 0.25...0.75)
        let spread = x == nil ? 0.12 : 0.04
        for _ in 0..<count {
            pellets.append(Pellet(x: min(0.97, max(0.03, center + .random(in: -spread...spread))), y: .random(in: -0.04...0.02)))
        }
    }

    func position(of id: UUID) -> (x: Double, y: Double)? {
        swimmers[id].map { ($0.x, $0.y) }
    }

    /// 同じ時刻で何度呼ばれても一度しか進めない。
    func step(to date: Date, fish: [Fish], decorations: [Decoration]) {
        let dt: Double
        if let lastDate {
            dt = min(0.1, max(0, date.timeIntervalSince(lastDate)))
            if dt == 0 { return }
        } else {
            dt = 0
        }
        lastDate = date
        time += dt
        sync(fish)
        for f in fish { if var s = swimmers[f.id] { move(&s, fish: f, dt: dt); swimmers[f.id] = s } }
        updatePellets(dt)
        updateBubbles(dt, decorations: decorations)
    }

    private func sync(_ fish: [Fish]) {
        let ids = Set(fish.map(\.id))
        swimmers = swimmers.filter { ids.contains($0.key) }
        for f in fish where swimmers[f.id] == nil {
            let (tx, ty) = randomTarget(for: f)
            swimmers[f.id] = Swimmer(x: f.x, y: f.y, targetX: tx, targetY: ty, facingRight: Bool.random())
        }
    }

    private func yRange(for f: Fish) -> ClosedRange<Double> {
        switch f.species.zone {
        case .upper: return 0.10...0.50
        case .any: return 0.10...0.78
        case .bottom: return 0.80...0.84
        }
    }

    private func randomTarget(for f: Fish) -> (Double, Double) {
        var range = yRange(for: f)
        // 弱った魚は下の方でじっとしがち
        if f.condition == .critical { range = max(range.lowerBound, 0.6)...max(range.upperBound, 0.82) }
        return (.random(in: 0.06...0.94), .random(in: range))
    }

    private func move(_ s: inout Swimmer, fish f: Fish, dt: Double) {
        guard f.isAlive else {
            // 死んだ魚は底へ沈んで止まる
            s.vx = 0
            s.y = min(Self.sandTop - 0.01, s.y + 0.03 * dt)
            return
        }
        var speed = f.species.speed
        switch f.condition {
        case .hungry: speed *= 0.85
        case .weak: speed *= 0.6
        case .critical: speed *= 0.35
        case .sick: speed *= 0.6
        default: break
        }
        if f.isElderly() { speed *= 0.75 }
        // 稚魚はちょこまか、成魚はゆったり
        speed *= 1.15 - 0.3 * f.growth

        // 近くに餌があれば向かう
        var chasing = false
        if f.condition != .critical, let (i, p) = nearestPellet(to: s), hypot((p.x - s.x) * aspect, p.y - s.y) < 0.6 {
            s.targetX = p.x
            s.targetY = min(p.y, 0.84)
            chasing = true
            speed *= 1.8
            if hypot((p.x - s.x) * aspect, p.y - s.y) < 0.025 { pellets.remove(at: i) }
        } else if time >= s.retargetAt || hypot((s.targetX - s.x) * aspect, s.targetY - s.y) < 0.02 {
            (s.targetX, s.targetY) = randomTarget(for: f)
            s.retargetAt = time + .random(in: 3...9)
        }

        let dx = (s.targetX - s.x) * aspect, dy = s.targetY - s.y
        let dist = max(0.0001, hypot(dx, dy))
        let desiredVX = dx / dist * speed / aspect
        let desiredVY = dy / dist * speed * 0.6
        let ease = min(1, dt * (chasing ? 3 : 1.2))
        s.vx += (desiredVX - s.vx) * ease
        s.vy += (desiredVY - s.vy) * ease
        s.x = min(0.97, max(0.03, s.x + s.vx * dt))
        s.y = min(0.84, max(0.05, s.y + s.vy * dt))
        // 向きの切り替えに少しゆとりを持たせる
        if s.vx > 0.004 { s.facingRight = true } else if s.vx < -0.004 { s.facingRight = false }
        s.phase += dt * (2 + speed * 30)
    }

    private func nearestPellet(to s: Swimmer) -> (Int, Pellet)? {
        var best: (Int, Pellet, Double)?
        for (i, p) in pellets.enumerated() where p.y > 0 {
            let d = hypot((p.x - s.x) * aspect, p.y - s.y)
            if best == nil || d < best!.2 { best = (i, p, d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    private func updatePellets(_ dt: Double) {
        for i in pellets.indices {
            if pellets[i].y < Self.sandTop - 0.01 {
                pellets[i].y += 0.035 * dt
                pellets[i].x += sin(time * 2 + Double(i)) * 0.002 * dt
            } else if pellets[i].landedAt == nil {
                pellets[i].landedAt = time
            }
        }
        pellets.removeAll { ($0.landedAt.map { time - $0 > 25 }) ?? false }
    }

    private func updateBubbles(_ dt: Double, decorations: [Decoration]) {
        bubbleClock += dt
        if bubbleClock > 0.35 {
            bubbleClock = 0
            let sources = decorations.filter { $0.isPlaced && $0.kind.bubbles > 0 }
            for d in sources where Double.random(in: 0...1) < d.kind.bubbles {
                bubbles.append(Bubble(x: d.x + .random(in: -0.005...0.005), y: Self.sandTop - 0.02, speed: .random(in: 0.08...0.14), wobble: .random(in: 0...6)))
            }
            // どの水槽でもときどき泡が上がる
            if Double.random(in: 0...1) < 0.08 {
                bubbles.append(Bubble(x: .random(in: 0.05...0.95), y: Self.sandTop, speed: .random(in: 0.06...0.1), wobble: .random(in: 0...6)))
            }
        }
        for i in bubbles.indices { bubbles[i].y -= bubbles[i].speed * dt }
        bubbles.removeAll { $0.y < 0.02 }
    }
}

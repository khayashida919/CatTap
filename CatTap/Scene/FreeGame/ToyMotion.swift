import CoreGraphics
import Foundation

/// おもちゃごとの動き方。
/// 猫が追いかけたくなる獲物の動き（素早く走る・ぴたっと止まる・その場でぴくぴく動く・こっそり歩いてから急に走り出す・
/// 画面の端に隠れて顔を出す・叩かれたら逃げる）の速さと割合を決める。動かす処理は ToyScene にある
struct ToyMotion {

    /// 設定画面で選ぶ動き方。rawValue は設定画面の UISegmentedControl のセグメント番号と対応している
    enum Style: Int, Codable, CaseIterable {
        /// すいすい: 1.0.4 までの動き。ときどき押し出されて画面の中を滑るように動き、ときどき止まる。
        /// 動かす処理は ToyScene にあり、ToyMotion の値は使わない
        case classic
        /// しのび足: 獲物らしい動き。ToyMotion の値で動かす
        case stealthy
    }

    /// 進む向きに合わせて、体の向きをどう変えるか
    enum Facing {
        /// 変えない
        case none
        /// 左右を反転する。facesRight は、画像が右を向いて描かれているか
        case flip(facesRight: Bool)
        /// 頭（画像の上）を進む向きへ回す
        case rotate
        /// 転がる（毛糸玉）
        case roll
    }

    /// 走るときの速さ（pt/秒）
    var dashSpeed: ClosedRange<CGFloat>
    /// 1回走る時間（秒）
    var dashDuration: ClosedRange<TimeInterval>
    /// 走り出してから、走る速さに届くまでの時間（秒）。0 なら走り出した瞬間にその速さになる
    var accelTime: TimeInterval
    /// 走っている間の減速の強さ（physicsBody.linearDamping）。小さいほど同じ速さで走り続ける
    var damping: CGFloat
    /// 走り終わったあとに止まる割合。止まらないときは、そのまま次の動きに移る
    var freezeChance: Double
    /// 止まっている時間（秒）
    var freezeDuration: ClosedRange<TimeInterval>
    /// true ならぴたっと止まり、false なら滑るように止まる
    var stopsAbruptly: Bool
    /// ぴたっと止まる直前に、速さをゆるめる時間（秒）。stopsAbruptly が true のときだけ使う
    var brakeTime: TimeInterval
    /// その場でぴくぴく動く割合
    var twitchChance: Double
    /// ぴくぴく動くときの速さ（pt/秒）
    var twitchSpeed: ClosedRange<CGFloat>
    /// こっそり歩く割合。歩いたあとは一瞬止まって、急に走り出す
    var sneakChance: Double
    /// こっそり歩くときの速さ（pt/秒）
    var sneakSpeed: ClosedRange<CGFloat>
    /// こっそり歩く時間（秒）
    var sneakDuration: ClosedRange<TimeInterval>
    /// 画面の端に隠れて、少しだけ顔を出す割合
    var hideChance: Double
    /// 叩かれたときや、すぐ近くを叩かれたときに逃げる速さ（pt/秒）
    var fleeSpeed: CGFloat
    var facing: Facing

    /// 走る・歩く・逃げる速さを factor 倍にする。画面の大きさに合わせるときに使う。
    /// ぴくぴく動く速さは、おもちゃの大きさに対する動きなので変えない
    func scaled(by factor: CGFloat) -> ToyMotion {
        var motion = self
        motion.dashSpeed = dashSpeed.lowerBound * factor...dashSpeed.upperBound * factor
        motion.sneakSpeed = sneakSpeed.lowerBound * factor...sneakSpeed.upperBound * factor
        motion.fleeSpeed = fleeSpeed * factor
        return motion
    }

    static func motion(for toy: Toy) -> ToyMotion {
        switch toy {
        case .standard(.bug):
            // 虫: ちょこちょこ走っては止まり、触角を動かすようにぴくぴくする。ゆっくり這うこともある
            return ToyMotion(dashSpeed: 180...360, dashDuration: 0.3...0.7, accelTime: 0.08, damping: 0.4,
                             freezeChance: 0.6, freezeDuration: 0.4...1.8, stopsAbruptly: true, brakeTime: 0.05,
                             twitchChance: 0.35, twitchSpeed: 50...110,
                             sneakChance: 0.18, sneakSpeed: 35...70, sneakDuration: 0.8...2.0,
                             hideChance: 0.12, fleeSpeed: 650, facing: .rotate)
        case .standard(.bird):
            // 鳥: 短く跳ねるように動き、ときどきとことこ歩く。驚くと勢いよく飛び立つ
            return ToyMotion(dashSpeed: 280...480, dashDuration: 0.15...0.3, accelTime: 0.03, damping: 1.5,
                             freezeChance: 0.55, freezeDuration: 0.4...1.5, stopsAbruptly: false, brakeTime: 0,
                             twitchChance: 0.25, twitchSpeed: 60...120,
                             sneakChance: 0.15, sneakSpeed: 40...70, sneakDuration: 0.6...1.4,
                             hideChance: 0.05, fleeSpeed: 900, facing: .none)
        case .standard(.fish):
            // 魚: 尾びれでぐっと加速してすーっと泳ぎ、ゆっくり止まる。ゆったり漂うこともある
            return ToyMotion(dashSpeed: 160...320, dashDuration: 0.7...1.5, accelTime: 0.2, damping: 0.6,
                             freezeChance: 0.35, freezeDuration: 0.4...1.2, stopsAbruptly: false, brakeTime: 0,
                             twitchChance: 0.1, twitchSpeed: 40...80,
                             sneakChance: 0.2, sneakSpeed: 40...80, sneakDuration: 1.0...2.5,
                             hideChance: 0.05, fleeSpeed: 700, facing: .flip(facesRight: false))
        case .mouse:
            // ねずみ: 素早く走ってぴたっと止まり、においをかぐようにぴくぴくする。
            // 壁ぞいをこっそり歩いてから急に走り出したり、物陰に隠れたりすることが多い
            return ToyMotion(dashSpeed: 380...650, dashDuration: 0.35...0.8, accelTime: 0.1, damping: 0.2,
                             freezeChance: 0.7, freezeDuration: 0.5...2.0, stopsAbruptly: true, brakeTime: 0.08,
                             twitchChance: 0.25, twitchSpeed: 50...100,
                             sneakChance: 0.2, sneakSpeed: 40...80, sneakDuration: 0.8...2.2,
                             hideChance: 0.25, fleeSpeed: 900, facing: .flip(facesRight: true))
        case .butterfly:
            // ちょうちょ: ひらひらと向きを変え続け、ほとんど止まらない
            return ToyMotion(dashSpeed: 120...240, dashDuration: 0.25...0.5, accelTime: 0.12, damping: 0.8,
                             freezeChance: 0.1, freezeDuration: 0.2...0.5, stopsAbruptly: false, brakeTime: 0,
                             twitchChance: 0, twitchSpeed: 0...0,
                             sneakChance: 0, sneakSpeed: 0...0, sneakDuration: 0...0,
                             hideChance: 0.03, fleeSpeed: 600, facing: .none)
        case .laser:
            // レーザーポインター: 一瞬で飛んでぴたっと止まり、止まっている間は手ぶれのように細かく震える。
            // ゆっくり這うように動いてから、急に飛ぶこともある
            return ToyMotion(dashSpeed: 700...1100, dashDuration: 0.12...0.25, accelTime: 0.04, damping: 0.1,
                             freezeChance: 0.75, freezeDuration: 0.3...1.4, stopsAbruptly: true, brakeTime: 0,
                             twitchChance: 0.35, twitchSpeed: 20...45,
                             sneakChance: 0.2, sneakSpeed: 30...70, sneakDuration: 1.0...2.5,
                             hideChance: 0.1, fleeSpeed: 1200, facing: .none)
        case .teaser:
            // ねこじゃらし: 振られているように動いては止まり、小刻みに揺れる。じわじわ近づくこともある
            return ToyMotion(dashSpeed: 220...420, dashDuration: 0.35...0.7, accelTime: 0.15, damping: 1.0,
                             freezeChance: 0.5, freezeDuration: 0.3...1.0, stopsAbruptly: false, brakeTime: 0,
                             twitchChance: 0.4, twitchSpeed: 60...120,
                             sneakChance: 0.12, sneakSpeed: 40...80, sneakDuration: 0.8...1.8,
                             hideChance: 0.08, fleeSpeed: 800, facing: .none)
        case .yarn:
            // 毛糸玉: 転がり始めは少しずつ速くなり、だんだん遅くなる。ゆっくり転がることもある
            return ToyMotion(dashSpeed: 220...480, dashDuration: 0.6...1.2, accelTime: 0.2, damping: 0.8,
                             freezeChance: 0.3, freezeDuration: 0.8...2.0, stopsAbruptly: false, brakeTime: 0,
                             twitchChance: 0, twitchSpeed: 0...0,
                             sneakChance: 0.1, sneakSpeed: 50...90, sneakDuration: 1.0...2.0,
                             hideChance: 0.05, fleeSpeed: 800, facing: .roll)
        case .photo:
            // 写真のおもちゃ: ねずみに近い動きで、向きは変えない（写真がさかさまにならないように）
            return ToyMotion(dashSpeed: 300...550, dashDuration: 0.35...0.8, accelTime: 0.1, damping: 0.3,
                             freezeChance: 0.65, freezeDuration: 0.5...1.8, stopsAbruptly: true, brakeTime: 0.08,
                             twitchChance: 0.25, twitchSpeed: 50...100,
                             sneakChance: 0.2, sneakSpeed: 40...80, sneakDuration: 0.8...2.0,
                             hideChance: 0.2, fleeSpeed: 850, facing: .none)
        }
    }
}

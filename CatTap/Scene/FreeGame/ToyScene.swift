import SpriteKit
import GameplayKit
import AVFoundation

final class ToyScene: SKScene {
    
    private lazy var toy = childNode(withName: "toy") as? SKSpriteNode
    private lazy var pointEffect = childNode(withName: "pointEffect") as? SKLabelNode
    private lazy var pointLabel = childNode(withName: "pointLabel") as? SKLabelNode
    private lazy var bestLabel = childNode(withName: "bestLabel") as? SKLabelNode
    private var waveEffect = SKShapeNode(rectOf: CGSize(width: 100, height: 100), cornerRadius: 1000)
    
    var score = 0 { didSet {
        if App.shared.bestScore < score {
            App.shared.bestScore = score
        }
    }}
    private var player: AVAudioPlayer?
    /// 今回のゲームで動かしているおもちゃ
    private var playingToy: Toy = .standard(.bug)
    /// 今回のおもちゃの動き方
    private var motion = ToyMotion.motion(for: .standard(.bug))
    /// 最後に画面を叩いた場所と時刻。おもちゃはそこから離れる向きに逃げる
    private var lastTouch: (point: CGPoint, time: TimeInterval)?
    /// 動いている間の音を最後に鳴らした時刻
    private var lastMoveSoundDate = Date.distantPast
    /// ぴくぴく動いているおもちゃ。その間は体の向きを変えない
    private var twitchingNodes = Set<ObjectIdentifier>()
    /// 設定画面で「すいすい」（1.0.4 までの動き）を選んでいるか
    private var isClassic = false
    /// すいすい: おもちゃを押し出す間隔（秒）
    private var impulseInterval: TimeInterval = 3
    /// すいすい: おもちゃを押し出す強さの倍率
    private var impulseScale: CGFloat = 1

    override func didMove(to view: SKView) {

        backgroundColor = .clear

        if let bug = toy {
            //個数を設定数だけ増やす
            if 1 < App.shared.count {
                for _ in 1...App.shared.count - 1 {
                    if let clone = bug.copy() as? SKSpriteNode {
                        addChild(clone)
                    }
                }
            }

            playingToy = Self.playableToy()
            isClassic = App.shared.motionStyle == .classic
            // 大きい画面でも同じ勢いに見えるように、画面の大きさに合わせて速さを変える
            motion = ToyMotion.motion(for: playingToy).scaled(by: Self.speedScale(for: size))
            toyNodes.forEach {
                setUp($0, as: playingToy)
                // すいすいでは、ToyScene.sks のぶつかり方の円をそのまま使う
                if !isClassic {
                    setUpPhysics($0)
                }
            }
        }
        
        if let pointEffect = pointEffect {
            pointEffect.alpha = 0
        }
        
        if let pointLabel = pointLabel {
            pointLabel.text = "\(score)P"
        }
        
        if let bestLabel = bestLabel {
            bestLabel.text = "\(App.shared.bestScore)P"
        }
        
        if isClassic {
            // すいすいでは 1.0.4 までと同じく、右と上だけ画面の外まで動けるように壁を置き、押し出しと止める処理を始める
            physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: frame.minX, y: frame.minY,
                                                             width: frame.width + 160, height: frame.height + 160))
            startClassicMotion()
            return
        }

        // 画面の縁を壁にする。おもちゃが画面の端で半分ほど隠れられるように、壁を少し外側に置く
        if let node = toyNodes.first {
            let margin = Self.bodyRadius(of: node) + max(node.size.width, node.size.height) * 0.05
            physicsBody = SKPhysicsBody(edgeLoopFrom: frame.insetBy(dx: -margin, dy: -margin))
        } else {
            physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        }
        
        // 重ならないように画面のあちこちに置き、少しずつずらして動き始める
        let area = frame.insetBy(dx: frame.width * 0.15, dy: frame.height * 0.15)
        toyNodes.forEach {
            if 1 < App.shared.count {
                $0.position = CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
            }
            scheduleNext($0, after: .random(in: 0.2...1.2))
        }
    }
    
    private var toyNodes: [SKSpriteNode] {
        children.compactMap { $0 as? SKSpriteNode }.filter { $0.name == "toy" }
    }

    /// 選ばれているおもちゃのうち、今使えるもの。
    /// プレミアムを持っていないときと、写真が見つからないときは虫に戻す
    private static func playableToy() -> Toy {
        let toy = App.shared.toy
        if toy.isPremium && !PremiumStore.shared.isPremium {
            return .standard(.bug)
        }
        if case .photo(let id) = toy, PhotoToyStore.image(for: id) == nil {
            return .standard(.bug)
        }
        return toy
    }

    /// おもちゃのノード1つに、見た目・大きさ・動きを設定する。
    /// 個数を増やしたあとのすべてのノードに対して呼ぶ
    private func setUp(_ node: SKSpriteNode, as toy: Toy) {
        let base = App.shared.size.cgSize
        switch toy {
        case .standard(let kind):
            node.texture = SKTexture(imageNamed: String(describing: kind))
            node.size = base
        case .laser:
            node.texture = SKTexture(image: ToyImage.laser)
            node.size = CGSize(width: base.width * 0.7, height: base.height * 0.7)
        case .teaser:
            node.texture = SKTexture(image: ToyImage.teaser)
            node.size = CGSize(width: base.width * 0.7, height: base.height * 1.4)
            // 左右に揺らす
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(toAngle: 0.3, duration: 0.4),
                SKAction.rotate(toAngle: -0.3, duration: 0.4),
            ])))
        case .mouse:
            node.texture = SKTexture(image: ToyImage.mouse)
            node.size = CGSize(width: base.width * 1.2, height: base.height * 0.8)
        case .butterfly:
            node.texture = SKTexture(image: ToyImage.butterfly)
            node.size = CGSize(width: base.width * 1.1, height: base.height * 0.95)
            // 羽をぱたぱたさせる
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scaleX(to: 0.35, duration: 0.12),
                SKAction.scaleX(to: 1, duration: 0.12),
            ])))
        case .yarn:
            node.texture = SKTexture(image: ToyImage.yarn)
            node.size = base
        case .photo(let id):
            if let image = PhotoToyStore.image(for: id) {
                node.texture = SKTexture(image: image)
                // 縦横比を保ったまま、大きさの設定の枠に収める
                let ratio = min(base.width / image.size.width, base.height / image.size.height)
                node.size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            }
        }
        //透明化設定されている場合のみアニメーション追加
        if App.shared.isHiddenMode {
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: TimeInterval(App.shared.intervalTime)),
                SKAction.fadeOut(withDuration: 1),
                SKAction.wait(forDuration: TimeInterval(App.shared.hiddenTime)),
                SKAction.fadeIn(withDuration: 1),
            ])))
        }
    }

    /// おもちゃの大きさに合わせた、当たり判定の円の半径
    private static func bodyRadius(of node: SKSpriteNode) -> CGFloat {
        min(node.size.width, node.size.height) * 0.4
    }

    /// おもちゃの大きさに合わせて、ぶつかり方の円を作り直す。
    /// 速さは動きの処理で直接決めるので、重さは気にしない
    private func setUpPhysics(_ node: SKSpriteNode) {
        let body = SKPhysicsBody(circleOfRadius: Self.bodyRadius(of: node))
        body.affectedByGravity = false
        body.restitution = 0.6
        body.friction = 0.2
        body.linearDamping = motion.damping
        body.angularDamping = 0.5
        // 毛糸玉のほかは回さない。向きは update(_:) で進む向きに合わせる
        if case .roll = motion.facing {
            body.allowsRotation = true
        } else {
            body.allowsRotation = false
            node.zRotation = 0
        }
        node.physicsBody = body
    }

    override func update(_ currentTime: TimeInterval) {
        if isClassic {
            // すいすいでは、ねずみだけ走っている向きに顔を向ける。止まりかけのときは向きを変えない
            guard playingToy == .mouse else { return }
            for node in toyNodes {
                guard let dx = node.physicsBody?.velocity.dx, 20 < abs(dx) else { continue }
                node.xScale = dx < 0 ? -1 : 1
            }
            return
        }
        for node in toyNodes {
            // ぴくぴく動いている間は向きを変えない（向きがちらつくため）
            guard !twitchingNodes.contains(ObjectIdentifier(node)),
                  let velocity = node.physicsBody?.velocity else { continue }
            let speed = hypot(velocity.dx, velocity.dy)
            switch motion.facing {
            case .none:
                break
            case .flip(let facesRight):
                guard Self.turnSpeed < abs(velocity.dx) else { continue }
                let movingRight = 0 < velocity.dx
                node.xScale = movingRight == facesRight ? 1 : -1
            case .rotate:
                // 頭を進む向きへ、少しずつ回す
                guard Self.turnSpeed < speed else { continue }
                let target = atan2(velocity.dy, velocity.dx) - .pi / 2
                var difference = target - node.zRotation
                while .pi < difference { difference -= .pi * 2 }
                while difference < -.pi { difference += .pi * 2 }
                node.zRotation += difference * 0.25
            case .roll:
                // 転がる速さに合わせて回す
                node.physicsBody?.angularVelocity = -velocity.dx / max(Self.bodyRadius(of: node), 1)
            }
        }
    }

    /// これより遅いときは、体の向きを変えない（止まりかけのときに向きが揺れないように）
    private static let turnSpeed: CGFloat = 12

    /// 画面の大きさに合わせて、走る速さを何倍にするか。
    /// 幅 390pt の iPhone を 1 として、画面の短い辺の長さに比例させる（0.9〜1.8 倍）
    private static func speedScale(for size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        guard 0 < shortSide else { return 1 }
        return min(max(shortSide / 390, 0.9), 1.8)
    }

    // MARK: - すいすい（1.0.4 までの動き）

    /// -10〜10 の乱数。押し出す強さと、止めるまでの秒数に使う
    private var random: Int { Int.random(in: -10...10) }

    private func startClassicMotion() {
        switch playingToy {
        case .laser, .mouse:
            // レーザーポインターとねずみは、短い間隔で素早く走らせる
            impulseInterval = 1.2
            impulseScale = 2
        case .butterfly:
            // ちょうちょは、こまめに向きを変えてゆっくり飛ばす
            impulseInterval = 0.8
            impulseScale = 0.6
        default:
            break
        }
        classicImpulse()
        classicPause()
    }

    /// 0〜10 秒ごとに、すべてのおもちゃを止める
    private func classicPause() {
        // ゲーム画面を閉じたらシーンが解放されて、繰り返しも止まるように弱く持つ
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(abs(random))) { [weak self] in
            guard let self else { return }
            self.toyNodes.forEach {
                $0.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
                $0.physicsBody?.angularVelocity = 0
            }
            self.classicPause()
        }
    }

    /// impulseInterval 秒ごとに、すべてのおもちゃを乱数の向きと強さで押し出す
    private func classicImpulse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + impulseInterval) { [weak self] in
            guard let self else { return }
            self.toyNodes.forEach {
                $0.physicsBody?.applyImpulse(CGVector(dx: CGFloat(self.random * 100) * self.impulseScale,
                                                      dy: CGFloat(self.random * 100) * self.impulseScale))
            }
            // 見えているおもちゃのどれか1つから、動き出した音を出す
            if let node = self.toyNodes.filter({ 0.5 < $0.alpha && self.frame.contains($0.position) }).randomElement() {
                self.playMoveSound(from: node)
            }
            self.classicImpulse()
        }
    }

    // MARK: - しのび足（獲物らしい動き）

    /// 動きを始める。前の動きは止める
    private func runMotion(_ node: SKSpriteNode, _ action: SKAction, twitching: Bool = false) {
        if twitching {
            twitchingNodes.insert(ObjectIdentifier(node))
        } else {
            twitchingNodes.remove(ObjectIdentifier(node))
        }
        node.run(action, withKey: "motion")
    }

    /// delay 秒後に、次の動き（走る・ぴくぴく・こっそり歩く・隠れる）を始める
    private func scheduleNext(_ node: SKSpriteNode, after delay: TimeInterval) {
        runMotion(node, nextAction(node, after: delay))
    }

    private func nextAction(_ node: SKSpriteNode, after delay: TimeInterval) -> SKAction {
        .sequence([
            .wait(forDuration: max(delay, 0)),
            .run { [weak self, weak node] in
                guard let self, let node else { return }
                self.nextBehavior(node)
            },
        ])
    }

    private func nextBehavior(_ node: SKSpriteNode) {
        let roll = Double.random(in: 0..<1)
        if roll < motion.hideChance {
            hide(node)
        } else if roll < motion.hideChance + motion.twitchChance {
            twitch(node)
        } else if roll < motion.hideChance + motion.twitchChance + motion.sneakChance {
            sneak(node)
        } else {
            dash(node)
        }
    }

    /// 選んだ向きへ走る。走り終わったら、止まるか、そのまま次の動きに移る。
    /// burst が true なら、走る速さの範囲の速いほう半分から選ぶ（隠れていたあとや、こっそり歩いたあとに急に走り出すとき）
    private func dash(_ node: SKSpriteNode, burst: Bool = false) {
        let angle = chooseDirection(for: node)
        let range = motion.dashSpeed
        let slowest = burst ? (range.lowerBound + range.upperBound) / 2 : range.lowerBound
        let speed = CGFloat.random(in: slowest...range.upperBound)
        node.physicsBody?.linearDamping = motion.damping
        playMoveSound(from: node)
        let duration = TimeInterval.random(in: motion.dashDuration)
        let accel = min(motion.accelTime, duration / 2)
        let then = Double.random(in: 0..<1) < motion.freezeChance
            ? freezeAction(node, after: duration - accel)
            : nextAction(node, after: duration - accel)
        runMotion(node, .sequence([accelerate(node, toward: angle, speed: speed, over: accel), then]))
    }

    /// angle の向きへ、duration 秒かけて speed まで加速する。
    /// 走り出しの速さは speed の 2 割で、はじめに大きく、あとになるほど少しずつ速くなる。
    /// 途中で壁に当たって跳ね返ったら、跳ね返った向きのまま加速を続ける
    private func accelerate(_ node: SKSpriteNode, toward angle: CGFloat, speed: CGFloat, over duration: TimeInterval) -> SKAction {
        var direction = CGVector(dx: cos(angle), dy: sin(angle))
        var started = false
        let ramp = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let body = node.physicsBody else { return }
            let velocity = body.velocity
            let current = hypot(velocity.dx, velocity.dy)
            // 1回目は前の動きの向きが残っているので、新しい向きを使う
            if started, 1 < current {
                direction = CGVector(dx: velocity.dx / current, dy: velocity.dy / current)
            }
            started = true
            let progress = 0 < duration ? min(CGFloat(elapsed) / CGFloat(duration), 1) : 1
            let ratio = 0.2 + 0.8 * (1 - (1 - progress) * (1 - progress))
            body.velocity = CGVector(dx: direction.dx * speed * ratio, dy: direction.dy * speed * ratio)
        }
        // 最後に、走る速さちょうどにそろえる
        let finish = SKAction.run { [weak node] in
            guard let body = node?.physicsBody else { return }
            let velocity = body.velocity
            let current = hypot(velocity.dx, velocity.dy)
            if started, 1 < current {
                direction = CGVector(dx: velocity.dx / current, dy: velocity.dy / current)
            }
            body.velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)
        }
        return 0 < duration ? .sequence([ramp, finish]) : finish
    }

    /// after 秒後に止まり、しばらくじっとしてから次の動きに移る
    private func freezeAction(_ node: SKSpriteNode, after delay: TimeInterval) -> SKAction {
        let delay = max(delay, 0)
        let stillness = TimeInterval.random(in: motion.freezeDuration)
        var steps: [SKAction] = []
        if motion.stopsAbruptly {
            // 止まる直前に少しだけゆるめてから、ぴたっと止まる
            let brake = min(motion.brakeTime, delay)
            steps.append(.wait(forDuration: delay - brake))
            if 0 < brake {
                steps.append(slowDown(over: brake))
            }
            steps.append(.run { [weak self, weak node] in
                guard let self, let body = node?.physicsBody else { return }
                body.velocity = .zero
                if case .roll = self.motion.facing {} else { body.angularVelocity = 0 }
            })
        } else {
            steps.append(.wait(forDuration: delay))
            // 滑るように止まる
            steps.append(.run { [weak node] in
                node?.physicsBody?.linearDamping = 5
            })
        }
        steps.append(.wait(forDuration: stillness))
        steps.append(.run { [weak self, weak node] in
            guard let self, let node else { return }
            node.physicsBody?.linearDamping = self.motion.damping
            self.nextBehavior(node)
        })
        return .sequence(steps)
    }

    /// 今の速さを、duration 秒かけて 3 割まで落とす
    private func slowDown(over duration: TimeInterval) -> SKAction {
        var initialSpeed: CGFloat?
        return .customAction(withDuration: duration) { node, elapsed in
            guard let body = node.physicsBody else { return }
            let velocity = body.velocity
            let current = hypot(velocity.dx, velocity.dy)
            guard 1 < current else { return }
            let initial = initialSpeed ?? current
            initialSpeed = initial
            let progress = min(CGFloat(elapsed) / CGFloat(duration), 1)
            let target = initial * (1 - 0.7 * progress)
            body.velocity = CGVector(dx: velocity.dx / current * target, dy: velocity.dy / current * target)
        }
    }

    /// その場で小さく、ぴくぴく動く
    private func twitch(_ node: SKSpriteNode) {
        var actions: [SKAction] = []
        for _ in 0..<Int.random(in: 3...5) {
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            let speed = CGFloat.random(in: motion.twitchSpeed)
            actions.append(.run { [weak node] in
                node?.physicsBody?.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            })
            actions.append(.wait(forDuration: 0.06))
            actions.append(.run { [weak node] in node?.physicsBody?.velocity = .zero })
            actions.append(.wait(forDuration: .random(in: 0.08...0.18)))
        }
        actions.append(nextAction(node, after: .random(in: 0.2...0.6)))
        runMotion(node, .sequence(actions), twitching: true)
    }

    /// ゆっくり、少しずつ曲がりながら歩く。歩き終わると一瞬止まり、急に走り出す。
    /// 猫が身構えてから飛びかかるきっかけを作る
    private func sneak(_ node: SKSpriteNode) {
        var angle = chooseDirection(for: node)
        let speed = CGFloat.random(in: motion.sneakSpeed)
        // 1 秒あたりに曲がる角度（ラジアン）
        let turnRate = CGFloat.random(in: -0.8...0.8)
        let duration = TimeInterval.random(in: motion.sneakDuration)
        var started = false
        var lastElapsed: CGFloat = 0
        node.physicsBody?.linearDamping = motion.damping
        let creep = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let body = node.physicsBody else { return }
            let velocity = body.velocity
            // 壁に当たって跳ね返ったら、跳ね返った向きに歩き続ける
            if started, 1 < hypot(velocity.dx, velocity.dy) {
                angle = atan2(velocity.dy, velocity.dx)
            }
            started = true
            angle += turnRate * (elapsed - lastElapsed)
            lastElapsed = elapsed
            body.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        }
        runMotion(node, .sequence([
            creep,
            .run { [weak node] in node?.physicsBody?.velocity = .zero },
            .wait(forDuration: .random(in: 0.1...0.35)),
            .run { [weak self, weak node] in
                guard let self, let node else { return }
                self.dash(node, burst: true)
            },
        ]))
    }

    /// いちばん近い画面の端へ走って半分ほど隠れ、しばらく顔だけ出してから急に出てくる
    private func hide(_ node: SKSpriteNode) {
        let position = node.position
        let distances: [(edge: Int, distance: CGFloat)] = [
            (0, position.x - frame.minX), (1, frame.maxX - position.x),
            (2, position.y - frame.minY), (3, frame.maxY - position.y),
        ]
        guard let nearest = distances.min(by: { $0.distance < $1.distance }) else {
            dash(node)
            return
        }
        let reach = max(node.size.width, node.size.height)
        let target: CGPoint
        switch nearest.edge {
        case 0: target = CGPoint(x: frame.minX - reach, y: position.y)
        case 1: target = CGPoint(x: frame.maxX + reach, y: position.y)
        case 2: target = CGPoint(x: position.x, y: frame.minY - reach)
        default: target = CGPoint(x: position.x, y: frame.maxY + reach)
        }
        let speed = motion.dashSpeed.upperBound
        let dx = target.x - position.x, dy = target.y - position.y
        let distance = max(hypot(dx, dy), 1)
        node.physicsBody?.linearDamping = motion.damping
        playMoveSound(from: node)
        // 壁に着いたら止まって、顔を出したまま長めにじっとする
        let travel = max(min(TimeInterval((distance - reach) / speed) + 0.1, 1.5), 0.1)
        let accel = min(motion.accelTime, travel / 2)
        runMotion(node, .sequence([
            accelerate(node, toward: atan2(dy, dx), speed: speed, over: accel),
            .wait(forDuration: travel - accel),
            .run { [weak node] in node?.physicsBody?.velocity = .zero },
            .wait(forDuration: .random(in: 0.8...2.5)),
            .run { [weak self, weak node] in
                guard let self, let node else { return }
                self.dash(node, burst: true)
            },
        ]))
    }

    /// 走る向きを決める。叩かれたばかりなら叩かれた場所から離れる向き、
    /// 画面の端の近くなら画面の内側寄りの向きにする
    private func chooseDirection(for node: SKSpriteNode) -> CGFloat {
        let position = node.position
        if let touch = lastTouch, CACurrentMediaTime() - touch.time < 1.5,
           hypot(position.x - touch.point.x, position.y - touch.point.y) < 320 {
            let away = atan2(position.y - touch.point.y, position.x - touch.point.x)
            return away + .random(in: -0.7...0.7)
        }
        let edgeX = frame.width * 0.15, edgeY = frame.height * 0.15
        let nearEdge = position.x < frame.minX + edgeX || frame.maxX - edgeX < position.x
            || position.y < frame.minY + edgeY || frame.maxY - edgeY < position.y
        if nearEdge {
            let toCenter = atan2(frame.midY - position.y, frame.midX - position.x)
            return toCenter + .random(in: -1.2...1.2)
        }
        return .random(in: 0..<(.pi * 2))
    }

    /// 叩かれたおもちゃと、すぐ近くを叩かれたおもちゃを、叩かれた場所から離れる向きへ逃がす。
    /// 驚いて逃げるので、加速せずに一気に逃げる。逃げたあとは少し止まって、次に飛びかかる隙を作る
    private func flee(from point: CGPoint) {
        lastTouch = (point, CACurrentMediaTime())
        for node in toyNodes {
            let dx = node.position.x - point.x, dy = node.position.y - point.y
            let reach = max(node.size.width, node.size.height) / 2 + 60
            guard hypot(dx, dy) < reach else { continue }
            let angle = atan2(dy, dx) + .random(in: -0.4...0.4)
            node.physicsBody?.linearDamping = motion.damping
            node.physicsBody?.velocity = CGVector(dx: cos(angle) * motion.fleeSpeed, dy: sin(angle) * motion.fleeSpeed)
            runMotion(node, freezeAction(node, after: .random(in: 0.35...0.6)))
        }
    }

    /// 動き出したおもちゃから、小さく音を出す。
    /// 鳴らしすぎないように、間をあけ、ときどき鳴らさずに見送る
    private func playMoveSound(from node: SKSpriteNode) {
        guard view != nil, let sound = ToySound.move(for: playingToy) else { return }
        let now = Date()
        guard ToySound.moveInterval(for: playingToy) <= now.timeIntervalSince(lastMoveSoundDate),
              Double.random(in: 0..<1) < 0.6 else { return }
        // 透明化で消えているものと、画面の外にいるものからは鳴らさない
        guard 0.5 < node.alpha, frame.contains(node.position) else { return }
        lastMoveSoundDate = now
        ToySoundPlayer.shared.play(sound, volume: 0.35, pan: pan(at: node.position))
    }

    /// 画面の左右の位置を、音の左右（-0.8〜0.8）に置き換える
    private func pan(at position: CGPoint) -> Float {
        guard 0 < frame.width else { return 0 }
        let ratio = (position.x - frame.minX) / frame.width
        return Float((ratio * 2 - 1) * 0.8)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isClassic, let node = toy {
            // すいすいでは、画面のどこを叩いても、最初のおもちゃを押し出す
            node.physicsBody?.applyImpulse(CGVector(dx: random * 100, dy: random * 100))
        }
        for touche in touches {
            let location = touche.location(in: self)
            if !isClassic {
                flee(from: location)
            }
            if let node = atPoint(location) as? SKSpriteNode {
                if node.name == "toy" {
                    score += 1
                    pointLabel?.text = "\(score)P"
                    bugTouchAction(atPoint: location)
                }
            }
        }
    }
    
    private func bugTouchAction(atPoint position : CGPoint) {
        Feedback.impact()
        // サウンド再生
        if let sound = ToySound.hit(for: playingToy) {
            // プレミアムのおもちゃは、おもちゃごとの音を鳴らす
            ToySoundPlayer.shared.play(sound, volume: 0.8, pan: pan(at: position))
        } else if let url = Bundle.main.url(forResource: "papa", withExtension: "mp3") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
        // ポイント表示エフェクト
        if let pointEffect = pointEffect?.copy() as? SKLabelNode {
            pointEffect.position = position
            pointEffect.alpha = 1
            pointEffect.run(SKAction.sequence([SKAction.group([SKAction.fadeOut(withDuration: 1),
                                                               SKAction.moveTo(y: position.y + 100, duration: 1)]),
                                               SKAction.removeFromParent()]))
            addChild(pointEffect)
        }
        // 波のエフェクト
        if let waveEffect = waveEffect.copy() as? SKShapeNode {
            waveEffect.lineWidth = 1
            waveEffect.position = position
            waveEffect.run(SKAction.sequence([SKAction.group([SKAction.scale(to: 10, duration: 1),
                                                              SKAction.fadeOut(withDuration: 0.5)]),
                                              SKAction.removeFromParent()]))
            addChild(waveEffect)
        }
    }
    
}

extension ToyScene: SKPhysicsContactDelegate {
    
}

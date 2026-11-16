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
    private var random: Int { Int.random(in: -10...10) }
    private var player: AVAudioPlayer?
    /// おもちゃを押し出す間隔（秒）
    private var impulseInterval: TimeInterval = 3
    /// おもちゃを押し出す強さの倍率
    private var impulseScale: CGFloat = 1
    /// 今回のゲームで動かしているおもちゃ
    private var playingToy: Toy = .standard(.bug)
    /// 動いている間の音を最後に鳴らした時刻
    private var lastMoveSoundDate = Date.distantPast

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
            children
                .compactMap { $0 as? SKSpriteNode }
                .filter { $0.name == "toy" }
                .forEach { setUp($0, as: playingToy) }

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
        
        let border = CGRect(x: frame.minX,
                          y: frame.minY,
                          width: frame.width + 160,
                          height: frame.height + 160)
        physicsBody = SKPhysicsBody(edgeLoopFrom: border)
        
        impulse()
        pause()
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
            // くるくる回さず、左右に揺らす
            node.physicsBody?.allowsRotation = false
            node.zRotation = 0
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(toAngle: 0.3, duration: 0.4),
                SKAction.rotate(toAngle: -0.3, duration: 0.4),
            ])))
        case .mouse:
            node.texture = SKTexture(image: ToyImage.mouse)
            node.size = CGSize(width: base.width * 1.2, height: base.height * 0.8)
            // 回さずに、走る向きへ顔を向ける（update(_:) で左右を反転する）
            node.physicsBody?.allowsRotation = false
            node.zRotation = 0
        case .butterfly:
            node.texture = SKTexture(image: ToyImage.butterfly)
            node.size = CGSize(width: base.width * 1.1, height: base.height * 0.95)
            node.physicsBody?.allowsRotation = false
            node.zRotation = 0
            // 羽をぱたぱたさせる
            node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scaleX(to: 0.35, duration: 0.12),
                SKAction.scaleX(to: 1, duration: 0.12),
            ])))
        case .yarn:
            // 毛糸玉はそのまま転がす
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

    override func update(_ currentTime: TimeInterval) {
        guard playingToy == .mouse else { return }
        // ねずみは走っている向きに顔を向ける。止まりかけのときは向きを変えない
        for node in children where node.name == "toy" {
            guard let dx = node.physicsBody?.velocity.dx, 20 < abs(dx) else { continue }
            node.xScale = dx < 0 ? -1 : 1
        }
    }

    private func pause() {
        // ゲーム画面を閉じたらシーンが解放されて、繰り返しも止まるように弱く持つ
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(abs(random))) { [weak self] in
            guard let self else { return }
            self.children
                .filter { $0.name == "toy" }
                .forEach {
                    $0.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
                    $0.physicsBody?.angularVelocity = 0
                }
            self.pause()
        }
    }
    
    private func impulse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + impulseInterval) { [weak self] in
            guard let self else { return }
            self.children
                .filter { $0.name == "toy" }
                .forEach {
                    $0.physicsBody?.applyImpulse(CGVector(dx: CGFloat(self.random * 100) * self.impulseScale,
                                                          dy: CGFloat(self.random * 100) * self.impulseScale))
                }
            self.playMoveSound()
            self.impulse()
        }
    }

    /// 動き出したおもちゃのどれか1つから、小さく音を出す。
    /// 鳴らしすぎないように、間をあけ、ときどき鳴らさずに見送る
    private func playMoveSound() {
        guard view != nil, let sound = ToySound.move(for: playingToy) else { return }
        let now = Date()
        guard ToySound.moveInterval(for: playingToy) <= now.timeIntervalSince(lastMoveSoundDate),
              Double.random(in: 0..<1) < 0.6 else { return }
        // 透明化で消えているものと、画面の外にいるものからは鳴らさない
        let visibleToys = children.filter { $0.name == "toy" && 0.5 < $0.alpha && frame.contains($0.position) }
        guard let node = visibleToys.randomElement() else { return }
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
        if let node = toy {
            node.physicsBody?.applyImpulse(CGVector(dx: random * 100, dy: random * 100))
        }
        
        for touche in touches {
            let location = touche.location(in: self)
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

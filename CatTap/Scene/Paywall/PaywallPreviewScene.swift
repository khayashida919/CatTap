import SpriteKit

/// 購入画面の上の窓で、プレミアムのおもちゃを動かして見せるシーン。
/// ゲームとは別に、窓の中だけで跳ね回らせる。
/// 押したおもちゃから開いたときは、そのおもちゃを大きくして主役にする
final class PaywallPreviewScene: SKScene {

    private let context: PaywallViewController.Context
    private var mouse: SKSpriteNode?

    init(size: CGSize, context: PaywallViewController.Context) {
        self.context = context
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.gravity = .zero
        updateEdges()

        for (index, toy) in Toy.premiumToys.enumerated() {
            let isMain: Bool
            if case .toy(let selected) = context {
                isMain = selected == toy
            } else {
                isMain = false
            }
            // 主役は大きく、ほかは少し小さく薄くする
            let scale: CGFloat
            switch context {
            case .general: scale = 1
            case .toy: scale = isMain ? 1.5 : 0.75
            case .photo: scale = 0.7
            }
            let node = addToy(image: Self.image(for: toy),
                              size: Self.baseSize(for: toy),
                              scale: scale,
                              allowsRotation: toy == .yarn,
                              index: index)
            if !isMain, context != .general {
                node.alpha = 0.6
            }
            if isMain {
                node.zPosition = 1
            }
            animate(node, as: toy)
        }

        // 写真から開いたときは、切り抜いた写真のおもちゃの見本を主役にする
        if context == .photo, let sample = UIImage(named: "photo_toy_sample") {
            let height: CGFloat = 96
            let node = addToy(image: sample,
                              size: CGSize(width: height * sample.size.width / sample.size.height, height: height),
                              scale: 1,
                              allowsRotation: false,
                              index: Toy.premiumToys.count / 2)
            node.zPosition = 1
            node.run(.repeatForever(.sequence([
                .wait(forDuration: 1.4),
                .run { node.physicsBody?.velocity = Self.randomVelocity(speed: 120) },
            ])))
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateEdges()
    }

    override func update(_ currentTime: TimeInterval) {
        // ねずみは走っている向きに顔を向ける（大きさを変えていても向きだけを反転する）
        if let mouse, let dx = mouse.physicsBody?.velocity.dx, 20 < abs(dx) {
            mouse.xScale = abs(mouse.xScale) * (dx < 0 ? -1 : 1)
        }
    }

    // MARK: - おもちゃ

    @discardableResult
    private func addToy(image: UIImage, size: CGSize, scale: CGFloat, allowsRotation: Bool, index: Int) -> SKSpriteNode {
        let nodeSize = CGSize(width: size.width * scale, height: size.height * scale)
        let node = SKSpriteNode(texture: SKTexture(image: image), size: nodeSize)
        let count = CGFloat(Toy.premiumToys.count + 1)
        node.position = CGPoint(x: self.size.width * CGFloat(index + 1) / count,
                                y: self.size.height * CGFloat.random(in: 0.35...0.65))
        let body = SKPhysicsBody(circleOfRadius: min(nodeSize.width, nodeSize.height) / 2)
        body.affectedByGravity = false
        body.allowsRotation = allowsRotation
        body.restitution = 1
        body.friction = 0
        body.linearDamping = 0
        body.angularDamping = 0
        // おもちゃどうしはすり抜けて、窓の縁でだけ跳ね返る
        body.categoryBitMask = 0x2
        body.collisionBitMask = 0x1
        node.physicsBody = body
        addChild(node)
        body.velocity = Self.randomVelocity(speed: 80)
        return node
    }

    /// おもちゃごとの動き方。ゲーム画面の動きに似せる
    private func animate(_ node: SKSpriteNode, as toy: Toy) {
        switch toy {
        case .mouse:
            // 走っては止まる
            mouse = node
            node.run(.repeatForever(.sequence([
                .run { node.physicsBody?.velocity = Self.randomVelocity(speed: 200) },
                .wait(forDuration: 0.7),
                .run { node.physicsBody?.velocity = .zero },
                .wait(forDuration: 0.6),
            ])))
        case .butterfly:
            // 羽をぱたぱたさせ、こまめに向きを変える
            let width = node.xScale
            node.run(.repeatForever(.sequence([
                .scaleX(to: width * 0.35, duration: 0.12),
                .scaleX(to: width, duration: 0.12),
            ])))
            node.run(.repeatForever(.sequence([
                .wait(forDuration: 0.8),
                .run { node.physicsBody?.velocity = Self.randomVelocity(speed: 60) },
            ])))
        case .laser:
            // 素早く飛んではぴたっと止まる
            node.run(.repeatForever(.sequence([
                .run { node.physicsBody?.velocity = Self.randomVelocity(speed: 300) },
                .wait(forDuration: 0.35),
                .run { node.physicsBody?.velocity = .zero },
                .wait(forDuration: 0.8),
            ])))
        case .teaser:
            // 左右に揺れる
            node.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.3, duration: 0.4),
                .rotate(toAngle: -0.3, duration: 0.4),
            ])))
        default:
            break
        }
    }

    private static func image(for toy: Toy) -> UIImage {
        ToyImage.thumbnail(for: toy) ?? ToyImage.laser
    }

    private static func baseSize(for toy: Toy) -> CGSize {
        switch toy {
        case .mouse: return CGSize(width: 72, height: 48)
        case .butterfly: return CGSize(width: 58, height: 50)
        case .laser: return CGSize(width: 44, height: 44)
        case .teaser: return CGSize(width: 36, height: 72)
        default: return CGSize(width: 54, height: 54)
        }
    }

    // MARK: - 壁と速さ

    /// 窓の縁を、跳ね返る壁にする
    private func updateEdges() {
        let edges = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        edges.categoryBitMask = 0x1
        physicsBody = edges
    }

    private static func randomVelocity(speed: CGFloat) -> CGVector {
        let angle = CGFloat.random(in: 0..<(.pi * 2))
        return CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
    }
}

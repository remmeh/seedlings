import SpriteKit
import UIKit

extension Fruit {
    var color: UIColor { [UIColor(hex: 0xE77B86), UIColor(hex: 0xEDB26F), UIColor(hex: 0xA8A3D6), UIColor(hex: 0xA6BF7A)][rawValue] }
    var darkColor: UIColor { [UIColor(hex: 0xAE495D), UIColor(hex: 0xB87936), UIColor(hex: 0x6C629F), UIColor(hex: 0x69874D)][rawValue] }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// All artwork is rendered natively. No remote assets, web views, or dependencies.
final class GameScene: SKScene {
    let engine: GameEngine
    var onTick: (() -> Void)?
    var onEvent: ((GameEvent) -> Void)?
    var steering: Direction?
    var frozen = false
    private let board = SKNode()
    private var sprites: [Int: SKNode] = [:]
    private var trails: [Int: SKShapeNode] = [:]
    private var territories: [Int: SKShapeNode] = [:]
    private var drawnTrails: [Int: [Cell]] = [:]
    private var marks = SKNode()
    private var lastTime: TimeInterval = 0
    private var hudClock: Double = 0
    private var drawnRevision = -1
    private var tile: CGFloat = 10
    private var inputOrigin: CGPoint?
    private var activeTouch: UITouch?
    private var stick = SKShapeNode(circleOfRadius: 32)
    private let knob = SKShapeNode(circleOfRadius: 13)
    var haptics = true

    init(engine: GameEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 900, height: 650))
        scaleMode = .resizeFill
        backgroundColor = UIColor(hex: 0xEAF0E5)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic scene") }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        guard board.parent == nil else { return }
        addChild(board)
        stick.strokeColor = UIColor(hex: 0x56745D).withAlphaComponent(0.35)
        stick.fillColor = .white.withAlphaComponent(0.5)
        stick.lineWidth = 2; stick.zPosition = 100; stick.isHidden = true
        knob.fillColor = UIColor(hex: 0x315E44).withAlphaComponent(0.65)
        knob.strokeColor = .clear; stick.addChild(knob); addChild(stick)
        buildBoard()
    }
    override func didChangeSize(_ oldSize: CGSize) {
        guard board.parent != nil else { return }
        buildBoard()
    }

    private func buildBoard() {
        board.removeAllChildren(); sprites = [:]; trails = [:]; territories = [:]; drawnTrails = [:]
        tile = min((size.width - 34) / CGFloat(GameEngine.width), (size.height - 42) / CGFloat(GameEngine.height))
        tile = max(1, tile)
        board.position = CGPoint(x: (size.width - CGFloat(GameEngine.width) * tile) / 2, y: (size.height - CGFloat(GameEngine.height) * tile) / 2)
        let island = CGMutablePath()
        for cell in engine.land { island.addRect(rect(cell)) }
        let shadow = SKShapeNode(path: island)
        shadow.fillColor = UIColor(hex: 0xB5C7AD); shadow.strokeColor = .clear
        shadow.position.y = -tile * 0.65; board.addChild(shadow)
        let sand = SKShapeNode(path: island)
        sand.fillColor = UIColor(hex: 0xFCF8ED); sand.strokeColor = UIColor(hex: 0xFFFFFF)
        sand.lineWidth = 3; sand.zPosition = 1; board.addChild(sand)
        // Quiet dots give unclaimed land a tactile, paper-like texture.
        let dots = CGMutablePath()
        for cell in engine.land where cell.x % 2 == 0 && cell.y % 2 == 0 {
            let point = point(cell)
            dots.addEllipse(in: CGRect(x: point.x - 0.7, y: point.y - 0.7, width: 1.4, height: 1.4))
        }
        let grain = SKShapeNode(path: dots)
        grain.fillColor = UIColor(hex: 0xC9C6B8); grain.strokeColor = .clear; grain.zPosition = 2; board.addChild(grain)
        for player in engine.players {
            let shape = SKShapeNode(); shape.fillColor = player.fruit.color; shape.strokeColor = .clear
            shape.zPosition = 3; territories[player.id] = shape; board.addChild(shape)
            let trail = SKShapeNode(); trail.strokeColor = player.fruit.darkColor; trail.lineWidth = tile * 0.42
            trail.lineCap = .round; trail.lineJoin = .round; trail.zPosition = 5
            trails[player.id] = trail; board.addChild(trail)
            let sprite = makeCharacter(player.fruit)
            sprite.zPosition = 10 + CGFloat(player.id) * 0.01
            sprites[player.id] = sprite; board.addChild(sprite)
        }
        marks = SKNode(); marks.zPosition = 4; board.addChild(marks)
        drawnRevision = -1; redrawTerritories(); drawPlayers()
    }

    private func point(_ cell: Cell) -> CGPoint {
        CGPoint(x: (CGFloat(cell.x) + 0.5) * tile, y: (CGFloat(cell.y) + 0.5) * tile)
    }
    private func rect(_ cell: Cell) -> CGRect {
        CGRect(x: CGFloat(cell.x) * tile, y: CGFloat(cell.y) * tile, width: tile + 0.12, height: tile + 0.12)
    }
    private func redrawTerritories() {
        guard drawnRevision != engine.revision else { return }
        drawnRevision = engine.revision
        for player in engine.players {
            let path = CGMutablePath()
            for (cell, owner) in engine.owners where owner == player.id { path.addRect(rect(cell)) }
            territories[player.id]?.path = path
        }
        marks.removeAllChildren()
        for (cell, owner) in engine.owners where cell.x % 4 == 0 && cell.y % 4 == 0 {
            let seed = SKShapeNode(ellipseOf: CGSize(width: tile * 0.25, height: tile * 0.4))
            seed.fillColor = engine.players[owner].fruit.darkColor.withAlphaComponent(0.42)
            seed.strokeColor = .clear; seed.zRotation = -0.4; seed.position = point(cell)
            marks.addChild(seed)
        }
    }

    private func makeCharacter(_ fruit: Fruit) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: tile * 3.3, height: tile * 1.3))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.12); shadow.strokeColor = .clear
        shadow.position.y = -tile * 1.4; node.addChild(shadow)
        let body: SKShapeNode
        if fruit == .watermelon {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -tile * 1.75, y: tile * 0.85))
            path.addLine(to: CGPoint(x: tile * 1.75, y: tile * 0.85))
            path.addQuadCurve(to: CGPoint(x: 0, y: -tile * 1.5), control: CGPoint(x: tile * 1.8, y: -tile * 1.1))
            path.addQuadCurve(to: CGPoint(x: -tile * 1.75, y: tile * 0.85), control: CGPoint(x: -tile * 1.8, y: -tile * 1.1))
            body = SKShapeNode(path: path)
            body.fillColor = UIColor(hex: 0xFA7C89); body.strokeColor = UIColor(hex: 0x447F5B); body.lineWidth = tile * 0.4
            for x: CGFloat in [-0.85, 0, 0.85] {
                let seed = SKShapeNode(ellipseOf: CGSize(width: tile * 0.13, height: tile * 0.26))
                seed.position = CGPoint(x: x * tile, y: tile * 0.48)
                seed.fillColor = UIColor(hex: 0x633A3D); seed.strokeColor = .clear; body.addChild(seed)
            }
        } else {
            body = SKShapeNode(circleOfRadius: tile * 1.5)
            body.fillColor = fruit.color; body.strokeColor = fruit.darkColor; body.lineWidth = tile * 0.18
            let leaf = SKShapeNode(ellipseOf: CGSize(width: tile, height: tile * 0.45))
            leaf.fillColor = UIColor(hex: 0x527F51); leaf.strokeColor = .clear
            leaf.position = CGPoint(x: tile * 0.35, y: tile * 1.5); leaf.zRotation = 0.4; body.addChild(leaf)
        }
        node.addChild(body)
        for x: CGFloat in [-0.55, 0.55] {
            let eye = SKShapeNode(circleOfRadius: tile * 0.14)
            eye.position = CGPoint(x: tile * x, y: -tile * 0.1)
            eye.fillColor = UIColor(hex: 0x383D32); eye.strokeColor = .clear; node.addChild(eye)
            let blush = SKShapeNode(ellipseOf: CGSize(width: tile * 0.48, height: tile * 0.23))
            blush.position = CGPoint(x: tile * x * 1.5, y: -tile * 0.45)
            blush.fillColor = UIColor(hex: 0xEF7891).withAlphaComponent(0.65); blush.strokeColor = .clear; node.addChild(blush)
        }
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: -tile * 0.23, y: -tile * 0.45))
        mouth.addQuadCurve(to: CGPoint(x: tile * 0.23, y: -tile * 0.45), control: CGPoint(x: 0, y: -tile * 0.7))
        let smile = SKShapeNode(path: mouth); smile.strokeColor = UIColor(hex: 0x383D32); smile.lineWidth = 1.5; node.addChild(smile)
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.name = "crown"; label.text = "♛"; label.fontSize = tile * 2.5
        label.fontColor = UIColor(hex: 0xD9A52E); label.position.y = tile * 2.1
        node.addChild(label)
        if fruit == engine.players[0].fruit {
            let you = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            you.text = "YOU"; you.fontSize = max(8, tile * 0.8); you.fontColor = UIColor(hex: 0x315E44)
            you.position.y = -tile * 2.7; node.addChild(you)
        }
        return node
    }

    private func drawPlayers() {
        let leader = engine.leader
        for player in engine.players {
            let sprite = sprites[player.id]!
            let target = point(player.position)
            // Subtle interpolation softens the discrete simulation without altering rules.
            sprite.position.x += (target.x - sprite.position.x) * 0.45
            sprite.position.y += (target.y - sprite.position.y) * 0.45
            if abs(sprite.position.x - target.x) > tile * 5 || abs(sprite.position.y - target.y) > tile * 5 { sprite.position = target }
            sprite.alpha = player.protection > 0 ? 0.55 + CGFloat(sin(engine.elapsed * 18) + 1) * 0.2 : 1
            sprite.childNode(withName: "crown")?.isHidden = player.id != leader
            guard drawnTrails[player.id] != player.trail else { continue }
            drawnTrails[player.id] = player.trail
            let path = CGMutablePath()
            if let anchor = player.anchor, !player.trail.isEmpty {
                path.move(to: point(anchor))
                for cell in player.trail { path.addLine(to: point(cell)) }
            }
            trails[player.id]?.path = path
            // Every character leaves little fruit-colored seeds behind.
            trails[player.id]?.children.forEach { $0.removeFromParent() }
            for (index, cell) in player.trail.enumerated() where index % 2 == 0 {
                let seed = SKShapeNode(ellipseOf: CGSize(width: tile * 0.35, height: tile * 0.62))
                seed.fillColor = player.fruit.darkColor; seed.strokeColor = .white.withAlphaComponent(0.6)
                seed.lineWidth = 0.8; seed.zRotation = -0.5; seed.position = point(cell)
                trails[player.id]?.addChild(seed)
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 0.08)
        lastTime = currentTime
        guard !frozen else { return }
        engine.update(dt: dt, direction: steering)
        redrawTerritories(); drawPlayers()
        let events = engine.events; engine.events.removeAll()
        for event in events {
            if case .captured(let id, let amount) = event, id == 0, amount > 0 {
                showCapture(amount)
                if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            if case .cut(let id) = event, id == 0, haptics { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            onEvent?(event)
        }
        hudClock += dt
        if hudClock > 0.12 || !events.isEmpty { hudClock = 0; onTick?() }
    }

    private func showCapture(_ count: Int) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "+\(count)"; label.fontColor = UIColor(hex: 0x315E44)
        label.fontSize = max(15, tile * 1.8); label.position = point(engine.players[0].position)
        label.position.y += tile * 3; label.zPosition = 30; board.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 35, duration: 0.9), .fadeOut(withDuration: 0.9)]), .removeFromParent()]))
    }

    func clearInput() {
        steering = nil; inputOrigin = nil; activeTouch = nil; stick.isHidden = true
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !frozen, activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch; inputOrigin = touch.location(in: self)
        stick.position = inputOrigin!; stick.isHidden = false; knob.position = .zero
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), let origin = inputOrigin, !frozen else { return }
        let location = touch.location(in: self)
        let dx = location.x - origin.x, dy = location.y - origin.y
        let length = hypot(dx, dy)
        knob.position = CGPoint(x: dx * min(1, 24 / max(1, length)), y: dy * min(1, 24 / max(1, length)))
        if length < 7 { steering = nil }
        else if abs(dx) > abs(dy) { steering = dx > 0 ? .right : .left }
        else { steering = dy > 0 ? .up : .down }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { clearInput() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
}

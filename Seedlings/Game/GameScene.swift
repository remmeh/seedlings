import SpriteKit
import UIKit
import AVFoundation

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
    var controlHeading: GamePoint?
    private let sounds: GameSoundPlaying
    var soundEnabled: Bool {
        get { sounds.enabled }
        set { sounds.enabled = newValue }
    }
    private var touchTarget: GamePoint?
    var frozen = false { didSet { if frozen { sounds.stopAll() } } }
    private let board = SKNode()
    private var sprites: [Int: SKNode] = [:]
    private var trails: [Int: SKShapeNode] = [:]
    private var territories: [Int: SKShapeNode] = [:]
    private var drawnTraceRevisions: [Int: Int] = [:]
    private var drawnSeedTrails: [Int: [Cell]] = [:]
    private var marks = SKNode()
    private var lastTime: TimeInterval = 0
    private var hudClock: Double = 0
    private var drawnRevision = -1
    private var tile: CGFloat = 10
    private var activeTouch: UITouch?
    private let touchMarker = SKShapeNode(circleOfRadius: 10)
    var haptics = true

    init(engine: GameEngine, sounds: GameSoundPlaying = GameAudio()) {
        self.engine = engine
        self.sounds = sounds
        super.init(size: CGSize(width: 900, height: 650))
        scaleMode = .resizeFill
        backgroundColor = UIColor(hex: 0xEAF0E5)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic scene") }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        view.preferredFramesPerSecond = 120
        guard board.parent == nil else { return }
        addChild(board)
        touchMarker.strokeColor = UIColor(hex: 0x315E44).withAlphaComponent(0.5)
        touchMarker.fillColor = .white.withAlphaComponent(0.2)
        touchMarker.lineWidth = 2; touchMarker.zPosition = 100; touchMarker.isHidden = true
        addChild(touchMarker)
        buildBoard()
    }
    override func willMove(from view: SKView) { sounds.stopAll() }

    override func didChangeSize(_ oldSize: CGSize) {
        guard board.parent != nil else { return }
        buildBoard()
    }

    private func buildBoard() {
        board.removeAllChildren(); sprites = [:]; trails = [:]; territories = [:]; drawnTraceRevisions = [:]; drawnSeedTrails = [:]
        tile = min((size.width - 34) / CGFloat(GameEngine.width), (size.height - 42) / CGFloat(GameEngine.height))
        tile = max(1, tile)
        board.position = CGPoint(x: (size.width - CGFloat(GameEngine.width) * tile) / 2, y: (size.height - CGFloat(GameEngine.height) * tile) / 2)
        let island = terrainPath(engine.land)
        let shadow = SKShapeNode(path: island)
        shadow.fillColor = UIColor(hex: 0xB5C7AD); shadow.strokeColor = .clear
        shadow.position.y = -tile * 0.65; board.addChild(shadow)
        let sand = SKShapeNode(path: island)
        sand.fillColor = UIColor(hex: 0xFCF8ED); sand.strokeColor = .clear
        sand.lineWidth = 3; sand.zPosition = 1; board.addChild(sand)
        // Quiet dots give unclaimed land a tactile, paper-like texture.
        let dots = CGMutablePath()
        for cell in engine.land where cell.x % 8 == 0 && cell.y % 8 == 0 {
            let point = point(cell)
            dots.addEllipse(in: CGRect(x: point.x - 0.7, y: point.y - 0.7, width: 1.4, height: 1.4))
        }
        let grain = SKShapeNode(path: dots)
        grain.fillColor = UIColor(hex: 0xC9C6B8); grain.strokeColor = .clear; grain.zPosition = 2; board.addChild(grain)
        for player in engine.players {
            let shape = SKShapeNode(); shape.fillColor = player.fruit.color; shape.strokeColor = .clear
            shape.zPosition = 3; territories[player.id] = shape; board.addChild(shape)
            let trail = SKShapeNode(); trail.strokeColor = player.fruit.darkColor; trail.lineWidth = max(2.5, tile * 0.85)
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
    private func point(_ location: GamePoint) -> CGPoint {
        CGPoint(x: (location.x + 0.5) * Double(tile), y: (location.y + 0.5) * Double(tile))
    }

    // Merge horizontal runs, avoiding thousands of individually stroked grid squares.
    private func terrainPath(_ cells: Set<Cell>) -> CGPath {
        let path = CGMutablePath()
        let rows = Dictionary(grouping: cells, by: \.y)
        for (y, row) in rows {
            let xs = row.map(\.x).sorted()
            guard var first = xs.first else { continue }
            var last = first
            func addRun() {
                path.addRect(CGRect(x: CGFloat(first) * tile, y: CGFloat(y) * tile,
                                    width: CGFloat(last - first + 1) * tile + 0.12, height: tile + 0.12))
            }
            for x in xs.dropFirst() {
                if x != last + 1 { addRun(); first = x }
                last = x
            }
            addRun()
        }
        return path
    }
    private func redrawTerritories() {
        guard drawnRevision != engine.revision else { return }
        drawnRevision = engine.revision
        for player in engine.players {
            territories[player.id]?.path = terrainPath(Set(engine.owners.compactMap { $0.value == player.id ? $0.key : nil }))
        }
        marks.removeAllChildren()
        for player in engine.players {
            let pattern = CGMutablePath()
            for (cell, owner) in engine.owners where owner == player.id && cell.x % 4 == 0 && cell.y % 4 == 0 {
                // Keep the pattern inside the territory rather than spilling over borders.
                guard [Direction.up, .right, .down, .left].allSatisfy({ engine.owners[cell.moved($0)] == owner }) else { continue }
                let seed = CGMutablePath()
                seed.move(to: CGPoint(x: 0, y: tile * 0.5))
                seed.addCurve(to: CGPoint(x: 0, y: -tile * 0.45),
                              control1: CGPoint(x: -tile * 0.55, y: -tile * 0.05),
                              control2: CGPoint(x: -tile * 0.3, y: -tile * 0.45))
                seed.addCurve(to: CGPoint(x: 0, y: tile * 0.5),
                              control1: CGPoint(x: tile * 0.3, y: -tile * 0.45),
                              control2: CGPoint(x: tile * 0.4, y: -tile * 0.1))
                seed.closeSubpath()
                let variation = CGFloat((cell.x * 31 + cell.y * 17) % 11) / 10
                let center = point(cell)
                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: -0.6 + variation * 1.2)
                pattern.addPath(seed, transform: transform)
            }
            let seeds = SKShapeNode(path: pattern)
            seeds.fillColor = player.fruit.darkColor.withAlphaComponent(0.32)
            seeds.strokeColor = .clear
            marks.addChild(seeds)
        }
    }

    private func makeCharacter(_ fruit: Fruit) -> SKNode {
        let tile = self.tile * 2
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
            sprite.position = point(player.location)
            sprite.alpha = player.protection > 0 ? 0.55 + CGFloat(sin(engine.elapsed * 18) + 1) * 0.2 : 1
            sprite.childNode(withName: "crown")?.isHidden = player.id != leader
            guard drawnTraceRevisions[player.id] != player.traceRevision else { continue }
            drawnTraceRevisions[player.id] = player.traceRevision
            let path = CGMutablePath()
            if let first = player.visualTrail.first {
                path.move(to: point(first))
                for location in player.visualTrail.dropFirst() { path.addLine(to: point(location)) }
            }
            trails[player.id]?.path = path
            guard drawnSeedTrails[player.id] != player.trail else { continue }
            drawnSeedTrails[player.id] = player.trail
            // Every character leaves little fruit-colored seeds behind.
            trails[player.id]?.children.forEach { $0.removeFromParent() }
            for (index, cell) in player.trail.enumerated() where index % 8 == 0 {
                let seed = SKShapeNode(ellipseOf: CGSize(width: tile * 0.7, height: tile * 1.24))
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
        if let touch = activeTouch { updateTouchTarget(at: touch.location(in: self)) }
        let before = engine.players[0].location
        let previousSeconds = Int(ceil(engine.timeRemaining))
        engine.update(dt: dt, heading: controlHeading, target: touchTarget)
        redrawTerritories(); drawPlayers()
        let events = engine.events; engine.events.removeAll()
        let wasCut = events.contains { if case .cut(0) = $0 { return true }; return false }
        let after = engine.players[0].location
        sounds.setMoving(!engine.finished && !wasCut && hypot(after.x - before.x, after.y - before.y) > 0.00001)
        let seconds = Int(ceil(engine.timeRemaining))
        if seconds < previousSeconds, (1...10).contains(seconds) { sounds.play(.countdown) }
        if engine.finished { sounds.stopAll() }
        for event in events {
            if case .captured(let id, let amount) = event, id == 0, amount > 0 {
                showCapture(amount)
                sounds.play(.capture)
                if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            if case .cut(0) = event {
                sounds.play(.snip)
                if haptics { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            }
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

    /// Convert through the board transform so targeting survives resizing and rotation.
    func gamePoint(at sceneLocation: CGPoint) -> GamePoint {
        let location = board.convert(sceneLocation, from: self)
        return GamePoint(x: Double(location.x / tile) - 0.5, y: Double(location.y / tile) - 0.5)
    }

    private func updateTouchTarget(at location: CGPoint) {
        touchTarget = gamePoint(at: location)
        touchMarker.position = location
        touchMarker.isHidden = false
        controlHeading = nil
    }

    func steer(with heading: GamePoint?) {
        controlHeading = heading
        touchTarget = nil; activeTouch = nil; touchMarker.isHidden = true
        if heading == nil { sounds.setMoving(false) }
    }

    func clearInput() {
        controlHeading = nil; touchTarget = nil; activeTouch = nil; touchMarker.isHidden = true
        sounds.setMoving(false)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !frozen, activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        updateTouchTarget(at: touch.location(in: self))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch), !frozen else { return }
        updateTouchTarget(at: touch.location(in: self))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { clearInput() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
}

// Short synthesized PCM effects keep the game offline and avoid external assets.
enum GameSound: CaseIterable {
    case movement, snip, capture, countdown
    var duration: Double {
        switch self {
        case .movement: return 0.48
        case .snip: return 0.22
        case .capture: return 0.55
        case .countdown: return 0.09
        }
    }
}

protocol GameSoundPlaying: AnyObject {
    var enabled: Bool { get set }
    func setMoving(_ moving: Bool)
    func play(_ sound: GameSound)
    func stopAll()
}

final class GameAudio: GameSoundPlaying {
    var enabled = true { didSet { if !enabled { stopAll() } } }
    private var players: [GameSound: AVAudioPlayer] = [:]
    private var prepared = false
    private var interrupted = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.interrupted = type == .began
            if type == .began { self?.stopAll() }
        }
    }

    deinit {
        players.values.forEach { $0.stop() }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        do {
            // Ambient respects the silent switch and mixes with the user's music.
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            for sound in GameSound.allCases {
                let player = try AVAudioPlayer(data: Self.waveData(for: sound))
                player.volume = sound == .movement ? 0.16 : 0.55
                player.numberOfLoops = sound == .movement ? -1 : 0
                player.prepareToPlay()
                players[sound] = player
            }
        } catch {
            players = [:]
        }
    }

    func setMoving(_ moving: Bool) {
        guard moving, enabled, !interrupted else {
            players[.movement]?.stop()
            players[.movement]?.currentTime = 0
            return
        }
        prepare()
        if let player = players[.movement], !player.isPlaying { player.play() }
    }

    func play(_ sound: GameSound) {
        guard enabled, !interrupted else { return }
        prepare()
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    func stopAll() {
        for player in players.values { player.stop(); player.currentTime = 0 }
    }

    static func waveData(for sound: GameSound) -> Data {
        let rate = 22_050
        let count = Int(sound.duration * Double(rate))
        var samples = Data(capacity: count * 2)
        var noiseState: UInt32 = 42
        var filteredNoise = 0.0
        for frame in 0..<count {
            let t = Double(frame) / Double(rate)
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let noise = Double(noiseState) / Double(UInt32.max) * 2 - 1
            filteredNoise += (noise - filteredNoise) * 0.15
            let fade = min(1, t / 0.005, (sound.duration - t) / 0.008)
            let value: Double
            switch sound {
            case .movement:
                let pulse = 0.5 + 0.5 * cos(2 * .pi * t / sound.duration * 4)
                value = (filteredNoise * 0.65 + sin(2 * .pi * 125 * t) * 0.08) * pulse
            case .snip:
                let envelope = exp(-t * 18)
                value = (sin(2 * .pi * (1_100 * t - 1_900 * t * t)) * 0.5 + noise * 0.3) * envelope
            case .capture:
                let notes = [523.25, 659.25, 783.99, 1_046.5]
                value = notes.enumerated().reduce(0.0) { result, note in
                    let local = t - Double(note.offset) * 0.075
                    guard local >= 0 else { return result }
                    let envelope = min(1, local / 0.006) * exp(-local * 12)
                    return result + sin(2 * .pi * note.element * local) * envelope * 0.3
                }
            case .countdown:
                value = sin(2 * .pi * 880 * t) * exp(-t * 35) * 0.5
            }
            var sample = Int16(max(-1, min(1, value * fade)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(36 + samples.count)); text("WAVEfmt ")
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(rate)); word(UInt32(rate * 2)); word(UInt16(2)); word(UInt16(16))
        text("data"); word(UInt32(samples.count)); data.append(samples)
        return data
    }
}

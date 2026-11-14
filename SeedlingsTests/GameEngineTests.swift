import XCTest
import SwiftUI
import SpriteKit
import AVFoundation
@testable import Seedlings

final class GameEngineTests: XCTestCase {
    private func fixture(twoPlayers: Bool = false) -> GameEngine {
        let engine = GameEngine(seed: 42)
        engine.land = Set((0..<12).flatMap { x in (0..<12).map { Cell(x: x, y: $0) } })
        engine.owners = [:]
        engine.players = [Contestant(id: 0, fruit: .watermelon, position: Cell(x: 2, y: 2))]
        for x in 0...2 { for y in 0...2 { engine.owners[Cell(x: x, y: y)] = 0 } }
        if twoPlayers {
            engine.players.append(Contestant(id: 1, fruit: .orange, position: Cell(x: 10, y: 10)))
            engine.owners[Cell(x: 10, y: 10)] = 1
        }
        engine.events = []
        return engine
    }

    private let loop = [Cell(x: 3, y: 2), Cell(x: 4, y: 2), Cell(x: 5, y: 2),
                        Cell(x: 5, y: 3), Cell(x: 5, y: 4), Cell(x: 4, y: 4),
                        Cell(x: 3, y: 4), Cell(x: 2, y: 4), Cell(x: 2, y: 3), Cell(x: 2, y: 2)]

    func testOpenTrailDoesNotAllocateLand() {
        let engine = fixture()
        engine.move(engine.players[0], to: Cell(x: 3, y: 2))
        XCTAssertEqual(engine.owners.count, 9)
        XCTAssertNil(engine.owners[Cell(x: 3, y: 2)])
        XCTAssertEqual(engine.players[0].trail.count, 1)
    }

    func testClosedLoopCapturesInteriorAndTrail() {
        let engine = fixture()
        for cell in loop { engine.move(engine.players[0], to: cell) }
        XCTAssertEqual(engine.owners[Cell(x: 4, y: 3)], 0)
        XCTAssertEqual(engine.owners[Cell(x: 5, y: 3)], 0)
        XCTAssertNil(engine.owners[Cell(x: 6, y: 3)])
        XCTAssertTrue(engine.players[0].trail.isEmpty)
    }

    func testLoopStealsOtherPlayersLand() {
        let engine = fixture(twoPlayers: true)
        engine.owners[Cell(x: 4, y: 3)] = 1
        for cell in loop { engine.move(engine.players[0], to: cell) }
        XCTAssertEqual(engine.owners[Cell(x: 4, y: 3)], 0)
        XCTAssertEqual(engine.owners[Cell(x: 10, y: 10)], 1)
    }

    func testEnemyCanCutTrailAndExistingLandSurvives() {
        let engine = fixture(twoPlayers: true)
        let player = engine.players[0], rival = engine.players[1]
        engine.move(player, to: Cell(x: 3, y: 2))
        rival.position = Cell(x: 4, y: 2)
        engine.move(rival, to: Cell(x: 3, y: 2))
        XCTAssertTrue(player.trail.isEmpty)
        XCTAssertEqual(engine.owners[player.position], 0)
        XCTAssertEqual(engine.counts[0], 9)
        XCTAssertGreaterThan(player.protection, 0)
    }

    func testSelfCrossingReturnsHome() {
        let engine = fixture()
        let local = engine.players[0]
        engine.move(local, to: Cell(x: 3, y: 2))
        engine.move(local, to: Cell(x: 4, y: 2))
        engine.move(local, to: Cell(x: 3, y: 2))
        XCTAssertTrue(local.trail.isEmpty)
        XCTAssertEqual(engine.owners[local.position], 0)
    }

    func testOceanAndNonAdjacentMovesAreRejected() {
        let engine = fixture()
        let local = engine.players[0]
        engine.move(local, to: Cell(x: 20, y: 2))
        XCTAssertEqual(local.position, Cell(x: 2, y: 2))
        local.position = Cell(x: 0, y: 0)
        engine.move(local, to: Cell(x: -1, y: 0))
        XCTAssertEqual(local.position, Cell(x: 0, y: 0))
    }

    func testAllEightDirectionsMoveOneNeighbor() {
        let origin = Cell(x: 5, y: 5)
        XCTAssertEqual(Set(Direction.allCases.map { origin.moved($0) }).count, 8)
        for direction in Direction.allCases {
            let engine = fixture()
            engine.players[0].position = origin
            let next = origin.moved(direction)
            engine.move(engine.players[0], to: next)
            XCTAssertEqual(engine.players[0].position, next)
            XCTAssertEqual(Direction.between(origin, next), direction)
        }
    }

    func testMotionIsContinuousAndUsesTheActualDragAngle() {
        let engine = fixture()
        let player = engine.players[0]
        engine.update(dt: 1.0 / 120, heading: GamePoint(x: 3, y: 1))
        XCTAssertEqual(player.position, Cell(x: 2, y: 2))
        XCTAssertGreaterThan(player.location.x, 2)
        XCTAssertGreaterThan(player.location.y, 2)
        XCTAssertEqual((player.location.x - 2) / (player.location.y - 2), 3, accuracy: 0.000001)
        XCTAssertEqual(hypot(player.location.x - 2, player.location.y - 2), 18.0 / 120, accuracy: 0.000001)
    }

    func testTravelSpeedIsIndependentOfHeadingAndFrameRate() {
        for frames in [30, 60, 120] {
            for heading in [GamePoint(x: 1, y: 0), GamePoint(x: 1, y: 1), GamePoint(x: 3, y: 1)] {
                let engine = fixture()
                for _ in 0..<(frames / 3) { engine.update(dt: 1.0 / Double(frames), heading: heading) }
                let location = engine.players[0].location
                XCTAssertEqual(hypot(location.x - 2, location.y - 2), 6, accuracy: 0.000001)
            }
        }
    }

    func testLiftStopsImmediatelyWithoutDriftOrIdleTimeAccumulation() {
        let engine = fixture()
        engine.update(dt: 0.01, direction: .right)
        let stopped = engine.players[0].location
        for _ in 0..<100 { engine.update(dt: 0.08) }
        XCTAssertEqual(engine.players[0].location, stopped)
        engine.update(dt: 0.01, direction: .right)
        XCTAssertEqual(engine.players[0].location.x - stopped.x, 0.18, accuracy: 0.000001)
    }

    func testLateFrameChecksIntermediateTrailCells() {
        let engine = fixture(twoPlayers: true)
        let rival = engine.players[1]
        rival.trail = [Cell(x: 3, y: 2)]
        rival.anchor = Cell(x: 4, y: 2)
        engine.update(dt: 0.08, direction: .right)
        XCTAssertTrue(engine.events.contains { if case .cut(1) = $0 { return true }; return false })
        XCTAssertGreaterThan(rival.protection, 0)
    }

    func testContinuousMotionStopsAtTheShoreAndResetSnapsLocationHome() {
        let engine = fixture()
        let player = engine.players[0]
        player.position = Cell(x: 11, y: 2)
        engine.update(dt: 0.08, direction: .right)
        XCTAssertEqual(player.position, Cell(x: 11, y: 2))
        XCTAssertEqual(player.location.cell, player.position)
        XCTAssertLessThan(player.location.x, 11.5)
        player.position = Cell(x: 2, y: 2)
        for cell in [Cell(x: 3, y: 3), Cell(x: 2, y: 3), Cell(x: 3, y: 2)] {
            engine.move(player, to: cell)
        }
        XCTAssertEqual(player.location, GamePoint(player.position))
        XCTAssertTrue(player.visualTrail.isEmpty)
    }

    private func shorelineFixture() -> GameEngine {
        let engine = fixture()
        engine.owners = Dictionary(uniqueKeysWithValues: engine.land.map { ($0, 0) })
        engine.owners[Cell(x: 0, y: 0)] = nil
        return engine
    }

    func testFruitSlidesAlongFlatShoreAtDifferentFrameRates() {
        var ends: [GamePoint] = []
        for fps in [30, 60, 120] {
            let engine = shorelineFixture()
            let player = engine.players[0]
            player.position = Cell(x: 11, y: 3)
            for _ in 0..<(fps / 2) {
                engine.update(dt: 1.0 / Double(fps), heading: GamePoint(x: 1, y: 1))
                XCTAssertTrue(engine.land.contains(player.location.cell))
                XCTAssertEqual(player.location.cell, player.position)
            }
            XCTAssertGreaterThan(player.location.y, 9)
            XCTAssertLessThan(player.location.x, 11.5)
            ends.append(player.location)
        }
        XCTAssertEqual(ends[0].y, ends[2].y, accuracy: 0.05)
        XCTAssertEqual(ends[0].x, ends[2].x, accuracy: 0.05)
    }

    func testFruitSlidesPastStaircaseShoreWithoutLeavingLand() {
        let engine = shorelineFixture()
        engine.land = Set((0..<64).flatMap { x in (0..<64).compactMap { y in
            x + y <= 50 ? Cell(x: x, y: y) : nil
        } })
        engine.owners = Dictionary(uniqueKeysWithValues: engine.land.map { ($0, 0) })
        engine.owners[Cell(x: 0, y: 0)] = nil
        let player = engine.players[0]
        player.position = Cell(x: 20, y: 29)
        for _ in 0..<120 {
            engine.update(dt: 1.0 / 120, target: GamePoint(x: 70, y: 50))
            XCTAssertTrue(engine.land.contains(player.location.cell))
            XCTAssertEqual(player.location.cell, player.position)
        }
        XCTAssertGreaterThan(player.location.x, 24)
        XCTAssertLessThan(player.location.y, 28)
        XCTAssertTrue(player.trail.isEmpty)
    }

    func testSlidingAlongGeneratedIslandShore() {
        for seed in UInt64(1)...UInt64(5) {
            let engine = GameEngine(seed: seed)
            let player = engine.players[0]
            engine.players = [player]
            engine.owners = Dictionary(uniqueKeysWithValues: engine.land.map { ($0, 0) })
            engine.owners[Cell(x: 64, y: 48)] = nil
            let start = engine.land.max { a, b in a.x == b.x ? a.y < b.y : a.x < b.x }!
            player.position = start
            for _ in 0..<120 {
                let before = player.location
                engine.update(dt: 1.0 / 60, target: GamePoint(x: 200, y: 200))
                XCTAssertTrue(engine.land.contains(player.location.cell))
                XCTAssertLessThanOrEqual(hypot(player.location.x - before.x, player.location.y - before.y), 18.0 / 60 + 0.000001)
            }
            XCTAssertGreaterThan(player.location.y, Double(start.y) + 5, "Shoreline seed \(seed) must keep sliding")
        }
    }

    func testPointingStraightOutwardStopsStablyAndCanTurnBackIn() {
        let engine = shorelineFixture()
        let player = engine.players[0]
        player.position = Cell(x: 11, y: 5)
        for _ in 0..<30 { engine.update(dt: 1.0 / 60, direction: .right) }
        let stopped = player.location
        for _ in 0..<30 { engine.update(dt: 1.0 / 60, direction: .right) }
        XCTAssertEqual(player.location.x, stopped.x, accuracy: 0.00001)
        XCTAssertEqual(player.location.y, stopped.y, accuracy: 0.00001)
        for _ in 0..<10 { engine.update(dt: 1.0 / 60, target: GamePoint(x: 2, y: 5)) }
        XCTAssertLessThan(player.location.x, 9)
    }

    func testTimerEndsRoundAtSixtySecondsWithoutAllocatingNeutralLand() {
        let engine = fixture(twoPlayers: true)
        let owners = engine.owners
        engine.elapsed = 59.97
        engine.update(dt: 0.08)
        XCTAssertTrue(engine.finished)
        XCTAssertEqual(engine.elapsed, 60, accuracy: 0.000001)
        XCTAssertEqual(engine.timeRemaining, 0)
        XCTAssertEqual(engine.owners, owners)
        XCTAssertEqual(engine.leader, 0)
        let position = engine.players[0].location
        engine.update(dt: 0.08, direction: .right)
        XCTAssertEqual(engine.players[0].location, position)
        XCTAssertEqual(engine.events.filter { if case .finished = $0 { return true }; return false }.count, 1)
    }

    func testTimerDeclaresRivalWinnerAndDoesNotFinishBeforeDeadline() {
        let engine = fixture(twoPlayers: true)
        engine.owners = Dictionary(uniqueKeysWithValues: engine.land.filter { $0.y < 5 }.map { ($0, 1) })
        engine.owners[engine.players[0].position] = 0
        engine.elapsed = 59.9
        engine.update(dt: 0.04)
        XCTAssertFalse(engine.finished)
        XCTAssertGreaterThan(engine.timeRemaining, 0)
        engine.elapsed = 60
        engine.update(dt: 0)
        XCTAssertTrue(engine.finished)
        XCTAssertEqual(engine.leader, 1)
    }

    func testStationaryFingerAttractsFruitAndStopsWithoutOvershoot() {
        let engine = fixture()
        let target = GamePoint(x: 6.2, y: 4.1)
        engine.update(dt: 1.0 / 120, target: target)
        XCTAssertGreaterThan(engine.players[0].location.x, 2)
        for _ in 0..<120 { engine.update(dt: 1.0 / 120, target: target) }
        XCTAssertEqual(engine.players[0].location.x, target.x, accuracy: 0.000001)
        XCTAssertEqual(engine.players[0].location.y, target.y, accuracy: 0.000001)
        let arrived = engine.players[0].location
        for _ in 0..<60 { engine.update(dt: 1.0 / 60, target: target) }
        XCTAssertEqual(engine.players[0].location, arrived)
    }

    func testFingerMovementRecomputesHeadingFromFruit() {
        let engine = fixture()
        engine.update(dt: 0.02, target: GamePoint(x: 8, y: 2))
        let before = engine.players[0].location
        engine.update(dt: 0.02, target: GamePoint(x: before.x, y: 8))
        XCTAssertEqual(engine.players[0].location.x, before.x, accuracy: 0.000001)
        XCTAssertEqual(engine.players[0].location.y - before.y, 0.36, accuracy: 0.000001)
    }

    func testCloseFingerTargetAndReleaseDoNotDrift() {
        let engine = fixture()
        let target = GamePoint(x: 2.01, y: 2.02)
        engine.update(dt: 0.08, target: target)
        XCTAssertEqual(engine.players[0].location.x, target.x, accuracy: 0.000001)
        XCTAssertEqual(engine.players[0].location.y, target.y, accuracy: 0.000001)
        let stopped = engine.players[0].location
        for _ in 0..<10 { engine.update(dt: 0.08) }
        XCTAssertEqual(engine.players[0].location, stopped)
    }

    @MainActor
    func testFingerCoordinatesMapToBoardAfterResize() {
        let scene = GameScene(engine: fixture())
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
        view.presentScene(scene)
        for size in [CGSize(width: 1194, height: 834), CGSize(width: 834, height: 1194)] {
            scene.size = size
            let tile = min((size.width - 34) / CGFloat(GameEngine.width), (size.height - 42) / CGFloat(GameEngine.height))
            let origin = CGPoint(x: (size.width - CGFloat(GameEngine.width) * tile) / 2,
                                 y: (size.height - CGFloat(GameEngine.height) * tile) / 2)
            let target = scene.gamePoint(at: CGPoint(x: origin.x + 20.75 * tile, y: origin.y + 12.25 * tile))
            XCTAssertEqual(target.x, 20.25, accuracy: 0.000001)
            XCTAssertEqual(target.y, 11.75, accuracy: 0.000001)
        }
    }

    func testDiagonalLoopCapturesInteriorAndTrail() {
        let engine = fixture()
        let loop = [Cell(x: 3, y: 3), Cell(x: 4, y: 4), Cell(x: 5, y: 3),
                    Cell(x: 6, y: 2), Cell(x: 5, y: 1), Cell(x: 4, y: 0),
                    Cell(x: 3, y: 1), Cell(x: 2, y: 2)]
        for cell in loop { engine.move(engine.players[0], to: cell) }
        XCTAssertTrue(engine.players[0].trail.isEmpty)
        XCTAssertEqual(engine.owners[Cell(x: 4, y: 2)], 0)
        XCTAssertTrue(loop.allSatisfy { engine.owners[$0] == 0 })
        XCTAssertNil(engine.owners[Cell(x: 7, y: 2)])
    }

    func testCrossingDiagonalEnemyTrailBetweenCellsCutsIt() {
        let engine = fixture(twoPlayers: true)
        let player = engine.players[0], rival = engine.players[1]
        engine.move(player, to: Cell(x: 3, y: 3))
        rival.position = Cell(x: 2, y: 3)
        engine.move(rival, to: Cell(x: 3, y: 2))
        XCTAssertTrue(player.trail.isEmpty)
        XCTAssertGreaterThan(player.protection, 0)
        XCTAssertEqual(engine.owners[player.position], 0)
    }

    func testCrossingOwnDiagonalTrailBetweenCellsReturnsHome() {
        let engine = fixture()
        let player = engine.players[0]
        for cell in [Cell(x: 3, y: 3), Cell(x: 2, y: 3), Cell(x: 3, y: 2)] {
            engine.move(player, to: cell)
        }
        XCTAssertTrue(player.trail.isEmpty)
        XCTAssertGreaterThan(player.protection, 0)
        XCTAssertEqual(engine.owners[player.position], 0)
    }

    func testDiagonalMovementRejectsOceanStationaryAndDistantCells() {
        let engine = fixture()
        let player = engine.players[0]
        let origin = player.position
        for cell in [origin, Cell(x: 4, y: 4), Cell(x: 3, y: 4)] {
            engine.move(player, to: cell)
            XCTAssertEqual(player.position, origin)
            XCTAssertTrue(player.trail.isEmpty)
        }
        engine.land.remove(Cell(x: 3, y: 3))
        engine.move(player, to: Cell(x: 3, y: 3))
        XCTAssertEqual(player.position, origin)
    }

    func testCrownFollowsLargestTerritoryAndBreaksTiesConsistently() {
        let engine = fixture(twoPlayers: true)
        XCTAssertEqual(engine.leader, 0)
        for x in 0..<11 { engine.owners[Cell(x: x, y: 11)] = 1 }
        XCTAssertEqual(engine.leader, 1)
        engine.owners = [Cell(x: 1, y: 1): 0, Cell(x: 10, y: 10): 1]
        XCTAssertEqual(engine.leader, 0)
    }

    func testRoundCanFinishEarlyWhenEveryCellIsAllocated() {
        let engine = fixture()
        engine.owners = Dictionary(uniqueKeysWithValues: engine.land.map { ($0, 0) })
        let last = Cell(x: 11, y: 11)
        engine.owners[last] = nil
        engine.update(dt: 0.01, direction: nil)
        XCTAssertFalse(engine.finished)
        engine.owners[last] = 0
        engine.update(dt: 0.01, direction: nil)
        XCTAssertTrue(engine.finished)
        XCTAssertEqual(engine.fractionAllocated, 1)
    }

    func testRandomIslandsAreConnectedAndFixedCanvasSize() {
        var shapes: Set<Set<Cell>> = []
        for seed in UInt64(1)...UInt64(30) {
            let engine = GameEngine(seed: seed)
            XCTAssertTrue(engine.land.allSatisfy { (0..<GameEngine.width).contains($0.x) && (0..<GameEngine.height).contains($0.y) })
            XCTAssertEqual(GameEngine.width, 128)
            XCTAssertEqual(GameEngine.height, 96)
            XCTAssertGreaterThan(engine.land.count, 4800)
            let start = engine.land.first!
            var visited: Set<Cell> = [start], queue = [start], head = 0
            while head < queue.count {
                let cell = queue[head]; head += 1
                for direction in Direction.allCases {
                    let neighbor = cell.moved(direction)
                    if engine.land.contains(neighbor), visited.insert(neighbor).inserted { queue.append(neighbor) }
                }
            }
            XCTAssertEqual(visited.count, engine.land.count)
            XCTAssertTrue(engine.players.allSatisfy { engine.owners[$0.position] == $0.id })
            shapes.insert(engine.land)
        }
        XCTAssertGreaterThan(shapes.count, 20)
    }

    @MainActor
    func testGamePlayfieldFillsTheWindow() {
        let session = GameSession()
        session.start()
        session.scene?.frozen = true
        let controller = UIHostingController(rootView: ContentView(session: session))
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("An iPad window scene is required"); return
        }
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func findSceneView(_ view: UIView) -> SKView? {
            if let scene = view as? SKView { return scene }
            return view.subviews.compactMap { findSceneView($0) }.first
        }
        guard let sceneView = findSceneView(controller.view) else {
            XCTFail("The native SpriteKit playfield must be present"); return
        }
        let frame = sceneView.convert(sceneView.bounds, to: window)
        XCTAssertEqual(frame.minX, 0, accuracy: 1)
        XCTAssertEqual(frame.minY, 0, accuracy: 1)
        XCTAssertEqual(frame.width, window.bounds.width, accuracy: 1)
        XCTAssertEqual(frame.height, window.bounds.height, accuracy: 1)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Fullscreen landscape gameplay"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    func testRivalsPlanCurvedSubCellRoutes() {
        let engine = GameEngine(seed: 19)
        engine.update(dt: 0.01)
        for rival in engine.players.dropFirst() {
            XCTAssertGreaterThan(rival.route.count, 60)
            XCTAssertTrue(rival.route.allSatisfy { engine.land.contains($0.cell) })
            let offsets = zip(rival.route, rival.route.dropFirst()).map {
                GamePoint(x: $1.x - $0.x, y: $1.y - $0.y)
            }
            XCTAssertGreaterThan(offsets.filter { abs($0.x) > 0.001 && abs($0.y) > 0.001 }.count, offsets.count / 2)
            for (a, b) in zip(offsets, offsets.dropFirst()) {
                XCTAssertLessThanOrEqual(a.length, 0.301)
                if let a = a.normalized, let b = b.normalized {
                    XCTAssertGreaterThan(a.x * b.x + a.y * b.y, 0.97)
                }
            }
        }
    }

    func testAnalogJoystickDeadZoneAndUnrestrictedAngle() {
        XCTAssertNil(GamePoint.joystick(dx: 3, dy: 2))
        let heading = GamePoint.joystick(dx: 30, dy: 10)!
        XCTAssertEqual(heading.length, 1, accuracy: 0.000001)
        XCTAssertEqual(heading.x / heading.y, 3, accuracy: 0.000001)
    }

    func testSynthesizedSoundFilesDecodeAndHaveSafeLevels() throws {
        for sound in GameSound.allCases {
            let data = GameAudio.waveData(for: sound)
            XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "RIFF")
            let player = try AVAudioPlayer(data: data)
            XCTAssertEqual(player.duration, sound.duration, accuracy: 1.0 / 22_050)
            XCTAssertEqual(player.numberOfChannels, 1)
            let bytes = Array(data.dropFirst(44))
            let samples = stride(from: 0, to: bytes.count, by: 2).map { index in
                Int(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8))
            }
            XCTAssertGreaterThan(samples.map { abs($0) }.max()!, 100)
            XCTAssertLessThan(samples.map { abs($0) }.max()!, 32_767)
            XCTAssertEqual(samples.first, 0)
            XCTAssertLessThan(abs(samples.last!), 500)
        }
    }

    private final class SoundSpy: GameSoundPlaying {
        var enabled = true
        var effects: [GameSound] = []
        var moving = false
        var stopCount = 0
        func setMoving(_ value: Bool) { moving = value && enabled }
        func play(_ sound: GameSound) { if enabled { effects.append(sound) } }
        func stopAll() { moving = false; stopCount += 1 }
    }

    @MainActor
    func testMovementAudioStopsOnReleaseAndPause() {
        let spy = SoundSpy()
        let scene = GameScene(engine: fixture(), sounds: spy)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        view.isPaused = true; view.presentScene(scene)
        scene.update(1)
        scene.steer(with: GamePoint(x: 1, y: 0))
        scene.update(1.02)
        XCTAssertTrue(spy.moving)
        scene.steer(with: nil)
        XCTAssertFalse(spy.moving)
        scene.update(1.04)
        XCTAssertFalse(spy.moving)
        scene.frozen = true
        XCTAssertGreaterThan(spy.stopCount, 0)
    }

    @MainActor
    func testLocalCaptureAndSnipPlayDistinctEffects() {
        let spy = SoundSpy()
        let engine = fixture()
        let scene = GameScene(engine: engine, sounds: spy)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        view.isPaused = true; view.presentScene(scene)
        scene.haptics = false
        engine.events = [.captured(1, 5), .cut(1), .captured(0, 0)]
        scene.update(1)
        XCTAssertTrue(spy.effects.isEmpty)
        engine.events = [.captured(0, 10), .cut(0)]
        scene.update(1.02)
        XCTAssertEqual(spy.effects, [.capture, .snip])
        XCTAssertFalse(spy.moving)
    }

    @MainActor
    func testCountdownTicksOnceForEachOfTheLastTenSeconds() {
        let spy = SoundSpy()
        let engine = fixture()
        let scene = GameScene(engine: engine, sounds: spy)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        view.isPaused = true; view.presentScene(scene)
        scene.update(1)
        XCTAssertTrue(spy.effects.isEmpty)
        var time = 1.0
        for second in stride(from: 10, through: 1, by: -1) {
            engine.elapsed = 60 - Double(second) - 0.01
            time += 0.02; scene.update(time)
            time += 0.02; scene.update(time)
        }
        XCTAssertEqual(spy.effects, Array(repeating: .countdown, count: 10))
        engine.elapsed = 59.99
        time += 0.02; scene.update(time)
        XCTAssertEqual(spy.effects.count, 10)
        XCTAssertGreaterThan(spy.stopCount, 0)
        XCTAssertTrue(engine.finished)
    }

    @MainActor
    func testRestartReplacesTheVisiblePausedSceneOnTheSameIsland() {
        let session = GameSession()
        session.start(level: 3, seed: 42)
        let oldScene = session.scene!
        let island = oldScene.engine.land
        let owners = oldScene.engine.owners
        oldScene.engine.elapsed = 25
        session.setPaused(true)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("An iPad window scene is required"); return
        }
        let window = UIWindow(windowScene: windowScene)
        let controller = UIHostingController(rootView: ContentView(session: session))
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        session.restart()
        XCTAssertEqual(session.timeRemaining, 60)
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func sceneView(_ view: UIView) -> SKView? {
            if let view = view as? SKView { return view }
            return view.subviews.compactMap { sceneView($0) }.first
        }
        XCTAssertFalse(session.scene === oldScene)
        XCTAssertTrue(sceneView(controller.view)?.scene === session.scene)
        XCTAssertFalse(session.paused)
        XCTAssertFalse(session.scene!.frozen)
        XCTAssertEqual(session.engine!.land, island)
        XCTAssertEqual(session.engine!.owners, owners)
        XCTAssertGreaterThan(session.timeRemaining, 59)
        XCTAssertLessThanOrEqual(session.timeRemaining, 60)
        XCTAssertEqual(session.level, 3)
        window.isHidden = true
    }

    func testBotsPreserveOwnershipInvariants() {
        let engine = GameEngine(seed: 19)
        for _ in 0..<6000 {
            engine.update(dt: 0.08, direction: nil)
            if engine.finished { break }
        }
        XCTAssertTrue(Set(engine.owners.keys).isSubset(of: engine.land))
        XCTAssertTrue(engine.owners.values.allSatisfy { (0..<4).contains($0) })
        XCTAssertTrue(engine.players.allSatisfy { engine.land.contains($0.position) })
        XCTAssertGreaterThan(engine.fractionAllocated, 0.1)
        XCTAssertTrue(engine.finished)
        XCTAssertEqual(engine.elapsed, GameEngine.roundDuration, accuracy: 0.000001)
    }
}

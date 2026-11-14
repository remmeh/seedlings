import XCTest
import SwiftUI
import SpriteKit
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

    func testJoystickSelectsEightSectorsAndStopsInDeadZone() {
        XCTAssertNil(Direction.steering(dx: 3, dy: 3))
        XCTAssertNil(Direction.steering(dx: 0, dy: 0))
        for direction in Direction.allCases {
            XCTAssertEqual(Direction.steering(dx: Double(direction.dx) * 20,
                                              dy: Double(direction.dy) * 20), direction)
        }
        XCTAssertEqual(Direction.steering(dx: 20, dy: 5), .right)
        XCTAssertEqual(Direction.steering(dx: 20, dy: 10), .upRight)
        XCTAssertEqual(Direction.steering(dx: -5, dy: -20), .down)
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

    func testJoystickPreservesAngleAndDeadZone() {
        XCTAssertNil(GamePoint.joystick(dx: 3, dy: 3))
        let heading = GamePoint.joystick(dx: 30, dy: 10)!
        XCTAssertEqual(heading.length, 1, accuracy: 0.000001)
        XCTAssertEqual(heading.x / heading.y, 3, accuracy: 0.000001)
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

    func testNoRoundEndUntilEveryCellIsAllocated() {
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

    func testBotsPreserveOwnershipInvariants() {
        let engine = GameEngine(seed: 19)
        for _ in 0..<6000 {
            engine.update(dt: 0.08, direction: nil)
            if engine.finished { break }
        }
        XCTAssertTrue(Set(engine.owners.keys).isSubset(of: engine.land))
        XCTAssertTrue(engine.owners.values.allSatisfy { (0..<4).contains($0) })
        XCTAssertTrue(engine.players.allSatisfy { engine.land.contains($0.position) })
        XCTAssertGreaterThan(engine.fractionAllocated, 0.5)
    }
}

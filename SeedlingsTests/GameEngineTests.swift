import XCTest
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
            XCTAssertTrue(engine.land.allSatisfy { (0..<64).contains($0.x) && (0..<48).contains($0.y) })
            XCTAssertGreaterThan(engine.land.count, 1200)
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

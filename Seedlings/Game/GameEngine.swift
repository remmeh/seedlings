import Foundation

struct Cell: Hashable {
    var x: Int
    var y: Int
    func isAdjacent(to other: Cell) -> Bool {
        self != other && abs(x - other.x) <= 1 && abs(y - other.y) <= 1
    }
    func moved(_ direction: Direction) -> Cell {
        Cell(x: x + direction.dx, y: y + direction.dy)
    }
}

/// Sub-cell coordinates keep motion independent of the territory grid and display refresh rate.
struct GamePoint: Equatable {
    var x: Double
    var y: Double
    init(x: Double, y: Double) { self.x = x; self.y = y }
    init(_ cell: Cell) { x = Double(cell.x); y = Double(cell.y) }
    var cell: Cell { Cell(x: Int(x.rounded()), y: Int(y.rounded())) }
    var length: Double { hypot(x, y) }
    var normalized: GamePoint? {
        guard length > 0.000001 else { return nil }
        return GamePoint(x: x / length, y: y / length)
    }
}

enum Direction: CaseIterable {
    case up, upRight, right, downRight, down, downLeft, left, upLeft
    var dx: Int {
        switch self {
        case .upRight, .right, .downRight: return 1
        case .upLeft, .left, .downLeft: return -1
        default: return 0
        }
    }
    var dy: Int {
        switch self {
        case .upLeft, .up, .upRight: return 1
        case .downLeft, .down, .downRight: return -1
        default: return 0
        }
    }
    static func between(_ a: Cell, _ b: Cell) -> Direction {
        allCases.first { $0.dx == (b.x - a.x).signum() && $0.dy == (b.y - a.y).signum() } ?? .up
    }
}

struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

enum Fruit: Int, CaseIterable {
    case watermelon, orange, blueberry, kiwi
    var name: String { ["Melon", "Clementine", "Blue", "Kiwi"][rawValue] }
    var emoji: String { ["🍉", "🍊", "🫐", "🥝"][rawValue] }
}

final class Contestant {
    let id: Int
    let fruit: Fruit
    var position: Cell { didSet { location = GamePoint(position) } }
    var location: GamePoint
    var traceRevision = 0
    var visualTrail: [GamePoint] = [] { didSet { traceRevision += 1 } }
    var previous: Cell
    var trail: [Cell] = []
    var anchor: Cell?
    var route: [Cell] = []
    var protection: Double = 0
    init(id: Int, fruit: Fruit, position: Cell) {
        self.id = id; self.fruit = fruit
        self.position = position; self.previous = position; self.location = GamePoint(position)
    }
}

enum GameEvent {
    case captured(Int, Int)
    case cut(Int)
    case finished
}

/// Pure Foundation rules. Coordinates are fixed-size cells, independent of screen size.
final class GameEngine {
    static let width = 128
    static let height = 96
    let level: Int
    var land: Set<Cell> = []
    var owners: [Cell: Int] = [:]
    var players: [Contestant] = []
    var events: [GameEvent] = []
    var revision = 0
    var elapsed: Double = 0
    var finished = false
    private var random: SeededRandom

    init(level: Int = 1, fruit: Fruit = .watermelon, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.level = level
        random = SeededRandom(state: seed)
        generateIsland()
        let starts = [Cell(x: 40, y: 34), Cell(x: 88, y: 62), Cell(x: 40, y: 62), Cell(x: 88, y: 34)]
        let fruits = [fruit] + Fruit.allCases.filter { $0 != fruit }
        for id in 0..<4 {
            let start = land.min { distance($0, starts[id]) < distance($1, starts[id]) }!
            players.append(Contestant(id: id, fruit: fruits[id], position: start))
            for x in -6...6 { for y in -6...6 where x*x + y*y <= 44 {
                let cell = Cell(x: start.x + x, y: start.y + y)
                if land.contains(cell) { owners[cell] = id }
            }}
        }
    }

    var counts: [Int] {
        var result = [Int](repeating: 0, count: players.count)
        for id in owners.values { result[id] += 1 }
        return result
    }
    /// A tied lead keeps the crown on the lower ID, consistently across frames.
    var leader: Int { counts.enumerated().max { a, b in a.element == b.element ? a.offset > b.offset : a.element < b.element }?.offset ?? 0 }
    var fractionAllocated: Double { Double(owners.count) / Double(max(land.count, 1)) }
    func percentage(_ id: Int) -> Double { Double(counts[id]) * 100 / Double(max(land.count, 1)) }
    func distance(_ a: Cell, _ b: Cell) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    private func generateIsland() {
        let phase = Double.random(in: 0...6.28, using: &random)
        for x in 0..<Self.width { for y in 0..<Self.height {
            let nx = (Double(x) - 63.5) / 58
            let ny = (Double(y) - 47.5) / 42
            let angle = atan2(ny, nx)
            let edge = 0.91 + 0.065 * sin(3 * angle + phase) + 0.045 * cos(5 * angle - phase) + 0.025 * sin(7 * angle + phase)
            if hypot(nx, ny) < edge { land.insert(Cell(x: x, y: y)) }
        }}
    }

    func update(dt: Double, direction: Direction? = nil, heading: GamePoint? = nil, target: GamePoint? = nil) {
        guard !finished else { return }
        let delta = min(max(dt, 0), 0.08)
        elapsed += delta
        let input = heading?.normalized ?? direction.flatMap {
            GamePoint(x: Double($0.dx), y: Double($0.dy)).normalized
        }
        for player in players {
            player.protection = max(0, player.protection - delta)
            let speed = player.id == 0 ? 18.0 : min(14.6, 10.0 + Double(level) * 0.6)
            if player.id == 0 {
                if let target {
                    // Recompute from the fruit on every frame, even when the finger is still.
                    let offset = GamePoint(x: target.x - player.location.x, y: target.y - player.location.y)
                    if let heading = offset.normalized {
                        _ = advance(player, heading: heading, distance: min(speed * delta, offset.length))
                    }
                } else if let input {
                    _ = advance(player, heading: input, distance: speed * delta)
                }
            } else {
                if player.route.isEmpty { planBot(player) }
                var remaining = speed * delta
                while remaining > 0.000001, let target = player.route.first {
                    guard target == player.position || player.position.isAdjacent(to: target) else {
                        player.route = []; break
                    }
                    let offset = GamePoint(x: Double(target.x) - player.location.x,
                                           y: Double(target.y) - player.location.y)
                    guard let heading = offset.normalized else { player.route.removeFirst(); continue }
                    let travel = min(remaining, offset.length)
                    guard advance(player, heading: heading, distance: travel) else {
                        player.route = []; break
                    }
                    remaining -= travel
                    if travel >= offset.length - 0.000001, !player.route.isEmpty { player.route.removeFirst() }
                }
            }
        }
        if owners.count == land.count {
            finished = true; events.append(.finished)
        }
    }

    /// Short substeps check every crossed cell, even when a display frame arrives late.
    @discardableResult
    private func advance(_ player: Contestant, heading: GamePoint, distance: Double) -> Bool {
        guard distance > 0 else { return true }
        let steps = max(1, Int(ceil(distance / 0.2)))
        let stride = distance / Double(steps)
        for _ in 0..<steps {
            let origin = player.location
            let next = GamePoint(x: origin.x + heading.x * stride, y: origin.y + heading.y * stride)
            if next.cell != player.position {
                let oldTrace = player.visualTrail
                let wasHome = player.trail.isEmpty
                guard move(player, to: next.cell) else { return false }
                if !player.trail.isEmpty { player.visualTrail = wasHome ? [origin] : oldTrace }
            }
            player.location = next
            if !player.trail.isEmpty {
                // Keep a smooth centerline rather than drawing the staircase of cell centers.
                player.visualTrail.append(next)
            }
        }
        return true
    }

    @discardableResult
    func move(_ player: Contestant, to next: Cell) -> Bool {
        guard !finished, land.contains(next), player.position.isAdjacent(to: next) else { return false }
        // An exposed trail can be cut; characters themselves never block movement.
        for rival in players where rival.id != player.id && rival.protection == 0 {
            if rival.trail.contains(next) || crossesTrail(of: rival, from: player.position, to: next) { reset(rival) }
        }
        if player.trail.contains(next) || crossesTrail(of: player, from: player.position, to: next) { reset(player); return false }
        player.previous = player.position
        player.position = next
        if owners[next] == player.id {
            if !player.trail.isEmpty { capture(player, home: next) }
        } else {
            if player.trail.isEmpty {
                player.anchor = player.previous
                player.visualTrail = [GamePoint(player.previous)]
            }
            player.trail.append(next)
            player.visualTrail.append(GamePoint(next))
        }
        return true
    }

    /// Opposing diagonal steps can cross between cell centers without sharing a cell.
    private func crossesTrail(of player: Contestant, from start: Cell, to end: Cell) -> Bool {
        guard start.x != end.x, start.y != end.y, let anchor = player.anchor else { return false }
        let points = [anchor] + player.trail
        return zip(points, points.dropFirst()).contains { a, b in
            a.x != b.x && a.y != b.y && a != start && b != start &&
                a.x + b.x == start.x + end.x && a.y + b.y == start.y + end.y
        }
    }

    private func capture(_ player: Contestant, home: Cell) {
        let oldOwners = owners
        // Close the loop through the player's existing land. This handles island-edge
        // loops without treating the ocean as a flood-fill escape route.
        let homePath = player.anchor.flatMap { anchor in
            shortestPath(from: home, to: anchor, allowed: { self.owners[$0] == player.id })
        }
        let polygon = player.trail + (homePath ?? [home])
        var claimed = Set(player.trail)
        if homePath != nil {
            for cell in land where isInside(cell, polygon: polygon) { claimed.insert(cell) }
        }
        for cell in claimed { owners[cell] = player.id }
        let gained = claimed.filter { oldOwners[$0] != player.id }.count
        player.trail = []; player.visualTrail = []; player.anchor = nil
        revision += 1
        events.append(.captured(player.id, gained))
        // Losing a home tile under an open trail is allowed. The trail can still
        // reconnect elsewhere; if all land is lost, respawn with a tiny foothold.
        for rival in players where !owners.values.contains(rival.id) { reset(rival) }
    }

    func isInside(_ cell: Cell, polygon: [Cell]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > cell.y) != (b.y > cell.y) {
                let edgeX = Double(b.x - a.x) * Double(cell.y - a.y) / Double(b.y - a.y) + Double(a.x)
                if Double(cell.x) < edgeX { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private func reset(_ player: Contestant) {
        player.trail = []; player.visualTrail = []; player.anchor = nil; player.route = []
        let homes = owners.keys.filter { owners[$0] == player.id }
        if let home = homes.min(by: { distance($0, player.position) < distance($1, player.position) }) {
            player.position = home
        } else {
            // Deterministic selection keeps seeded test games reproducible.
            let choices = land.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
            let home = choices[Int.random(in: 0..<choices.count, using: &random)]
            player.position = home
            owners[home] = player.id
            for direction in Direction.allCases {
                let neighbor = home.moved(direction)
                if land.contains(neighbor) { owners[neighbor] = player.id }
            }
            revision += 1
        }
        player.previous = player.position
        player.protection = 1.5
        events.append(.cut(player.id))
    }

    func shortestPath(from start: Cell, to target: Cell, allowed: (Cell) -> Bool) -> [Cell]? {
        if start == target { return [start] }
        var queue = [start], head = 0
        var visited: Set<Cell> = [start]
        var parent: [Cell: Cell] = [:]
        while head < queue.count {
            let cell = queue[head]; head += 1
            for direction in Direction.allCases {
                let next = cell.moved(direction)
                guard land.contains(next), !visited.contains(next), allowed(next) else { continue }
                parent[next] = cell
                if next == target {
                    var path = [next], cursor = next
                    while cursor != start { cursor = parent[cursor]!; path.append(cursor) }
                    return Array(path.reversed())
                }
                visited.insert(next); queue.append(next)
            }
        }
        return nil
    }

    private func planBot(_ player: Contestant) {
        // Rectangular excursions form readable, stealable loops.
        for _ in 0..<32 {
            let dx = Int.random(in: 8...26, using: &random) * (Bool.random(using: &random) ? 1 : -1)
            let dy = Int.random(in: 8...22, using: &random) * (Bool.random(using: &random) ? 1 : -1)
            let origin = player.position
            let corners = [Cell(x: origin.x + dx, y: origin.y), Cell(x: origin.x + dx, y: origin.y + dy), Cell(x: origin.x, y: origin.y + dy), origin]
            var path: [Cell] = [], cursor = origin
            for corner in corners {
                while cursor != corner {
                    cursor = cursor.moved(Direction.between(cursor, corner)); path.append(cursor)
                }
            }
            if path.allSatisfy({ land.contains($0) }) && path.contains(where: { owners[$0] != player.id }) {
                player.route = path; return
            }
        }
        // Find a remaining neutral tile (even in narrow bays), then return by a
        // different path so the last few cells can be claimed without a timer.
        let targets = land.filter { owners[$0] == nil }.sorted { distance($0, player.position) < distance($1, player.position) }
        for target in targets.prefix(16) {
            guard let out = shortestPath(from: player.position, to: target, allowed: { _ in true }) else { continue }
            let blocked = Set(out.dropFirst().dropLast())
            if let back = shortestPath(from: target, to: player.position, allowed: { !blocked.contains($0) }) {
                player.route = Array(out.dropFirst()) + Array(back.dropFirst()); return
            }
        }
        // Reposition on home ground, keeping exposed trails intact until reentry.
        let homes = owners.keys.filter { owners[$0] == player.id }
        if let destination = homes.randomElement(using: &random),
           let path = shortestPath(from: player.position, to: destination, allowed: { !player.trail.contains($0) }) {
            player.route = Array(path.dropFirst())
        }
    }
}

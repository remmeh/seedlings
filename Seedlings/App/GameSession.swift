import SwiftUI
import Combine

final class GameSession: ObservableObject {
    @Published var scene: GameScene?
    @Published var level = 1
    @Published var selectedFruit: Fruit = .watermelon
    @Published var scores: [Int] = [0, 0, 0, 0]
    @Published var allocated: Double = 0
    @Published var leader = 0
    @Published var paused = false
    @Published var complete = false
    @Published var showHelp = false
    @Published var status = "A little loop. A lot of land."
    @Published var haptics = UserDefaults.standard.object(forKey: "seedlings.haptics") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(haptics, forKey: "seedlings.haptics")
            scene?.haptics = haptics
        }
    }
    @Published var best = UserDefaults.standard.double(forKey: "seedlings.best") {
        didSet { UserDefaults.standard.set(best, forKey: "seedlings.best") }
    }

    var engine: GameEngine? { scene?.engine }

    func start(level: Int = 1) {
        self.level = level; complete = false; paused = false
        let engine = GameEngine(level: level, fruit: selectedFruit)
        let newScene = GameScene(engine: engine)
        newScene.haptics = haptics
        newScene.onTick = { [weak self] in self?.refresh() }
        newScene.onEvent = { [weak self, weak newScene] event in
            guard let self else { return }
            switch event {
            case .captured(let id, let count):
                if id == 0 { self.status = "Sweet! \(count) little patches claimed." }
            case .cut(let id):
                if id == 0 { self.status = "Trail snipped! You're safe back at home." }
            case .finished:
                self.complete = true; newScene?.clearInput(); newScene?.frozen = true
                self.best = max(self.best, engine.percentage(0))
            }
        }
        scene = newScene; status = "Leave home, make a loop, come back."
        refresh()
    }

    func refresh() {
        guard let engine else { return }
        scores = engine.counts; allocated = engine.fractionAllocated; leader = engine.leader
    }

    func setPaused(_ value: Bool) {
        paused = value; scene?.clearInput(); scene?.frozen = value || complete || showHelp
    }

    func setHelp(_ value: Bool) {
        showHelp = value; scene?.clearInput(); scene?.frozen = value || paused || complete
    }

    func menu() {
        scene?.onTick = nil; scene?.onEvent = nil; scene?.clearInput()
        scene = nil; complete = false; paused = false
    }
}

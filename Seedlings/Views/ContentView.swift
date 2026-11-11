import SwiftUI
import SpriteKit

extension Color {
    static let ink = Color(red: 0.17, green: 0.29, blue: 0.21)
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    static let moss = Color(red: 0.30, green: 0.43, blue: 0.32)
}

struct ContentView: View {
    @StateObject private var session = GameSession()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.paper.ignoresSafeArea()
                if let scene = session.scene {
                    game(scene, wide: geometry.size.width > 850)
                } else {
                    home(wide: geometry.size.width > 850)
                }
                if session.paused && !session.complete { pauseOverlay }
                if session.complete { resultsOverlay }
            }
            .foregroundStyle(Color.ink)
        }
        .sheet(isPresented: Binding(get: { session.showHelp }, set: { session.setHelp($0) })) { help }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session.scene != nil { session.setPaused(true) }
        }
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill").rotationEffect(.degrees(-25))
            Text("seedlings").font(.system(size: 25, weight: .heavy, design: .rounded))
        }.foregroundStyle(Color.ink)
    }

    private func home(wide: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                wordmark
                Spacer()
                Text("A LITTLE WORLD TO MAKE YOURS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Color.moss)
                iconButton("questionmark", label: "How to play") { session.setHelp(true) }
            }.padding(.horizontal, 32).padding(.top, 22)
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 50) {
                        homeCopy.frame(width: 360)
                        IslandIllustration(fruit: session.selectedFruit).frame(width: 440, height: 450)
                    }.padding(35)
                    VStack(spacing: 12) {
                        IslandIllustration(fruit: session.selectedFruit).frame(height: 260)
                        homeCopy.frame(maxWidth: 420)
                    }.padding(28)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 9) {
                Circle().fill(Color.moss).frame(width: 6, height: 6)
                Text("One island. Four little rivals. Endless fresh starts.")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Color.moss)
            }.padding(.bottom, 20)
        }
    }

    private var homeCopy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SMALL FRUIT, BIG AMBITIONS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2.2).foregroundStyle(Color.moss)
            Text("Make a little\nland grab.").font(.system(size: 55, weight: .heavy, design: .rounded)).tracking(-2).lineSpacing(-4)
                .accessibilityAddTraits(.isHeader)
            Text("Wander out. Leave a trail. Loop back home.\nTurn a tiny patch into your very own kingdom.")
                .font(.system(size: 16, weight: .medium, design: .rounded)).lineSpacing(6).foregroundStyle(Color.moss)
            VStack(alignment: .leading, spacing: 12) {
                Text("PICK YOUR LITTLE SELF").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5)
                HStack(spacing: 12) {
                    ForEach(Fruit.allCases, id: \.rawValue) { fruit in
                        Button { session.selectedFruit = fruit } label: {
                            FruitSticker(fruit: fruit).frame(width: 47, height: 47).padding(7)
                                .background(session.selectedFruit == fruit ? Color.white : Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(session.selectedFruit == fruit ? Color.moss : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(fruit.name)
                            .accessibilityAddTraits(session.selectedFruit == fruit ? .isSelected : [])
                    }
                }
            }.padding(.top, 8)
            Button { session.start() } label: {
                HStack {
                    Spacer(); Text("Let's grow").font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right").fontWeight(.bold); Spacer()
                }.padding(20).foregroundStyle(.white).background(Color.ink, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
            HStack(spacing: 6) {
                Image(systemName: "ipad.landscape")
                Text("Made for touch · Play offline · 3 fruit rivals")
            }.font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Color.moss)
            if session.best > 0 {
                Text("Your best harvest: \(session.best, specifier: "%.1f")% of the island")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color.moss)
            }
        }
    }

    private func game(_ scene: GameScene, wide: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                wordmark
                Text("ISLAND \(String(format: "%02d", session.level))")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.4)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(.white.opacity(0.7), in: Capsule())
                Spacer()
                iconButton("questionmark", label: "How to play") { session.setHelp(true) }
                iconButton("pause.fill", label: "Pause game") { session.setPaused(true) }
            }.padding(.top, 12)
            HStack(spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    SpriteView(scene: scene).clipShape(RoundedRectangle(cornerRadius: 30))
                        .accessibilityLabel("Island game board")
                        .accessibilityHint("Drag to steer, or use the direction buttons below.")
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                        Text("Drag anywhere to steer")
                    }.font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.moss).padding(12)
                        .background(Color.white.opacity(0.75), in: Capsule()).padding(16).allowsHitTesting(false)
                }
                if wide { sidebar.frame(width: 212) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !wide { compactScores }
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.status).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Reconnect to your color to claim the loop. Protect your trail!")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Color.moss)
                }.accessibilityElement(children: .combine)
                Spacer()
                directionButtons(scene)
            }.padding(.bottom, 10)
        }.padding(.horizontal, 24)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("THE PATCH").tracking(1.8); Spacer(); Image(systemName: "flag.fill") }
                .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Color.moss)
            VStack(spacing: 10) {
                ForEach(ranked, id: \.self) { id in scoreRow(id) }
            }
            Divider().overlay(Color.ink.opacity(0.1))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Island claimed").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(session.allocated * 100, specifier: "%.0f")%")
                        .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                }
                ProgressView(value: session.allocated).tint(Color.moss)
                Text("The round ends when every little patch has a home.")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).lineSpacing(4).foregroundStyle(Color.moss)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "crown.fill").font(.system(size: 25)).foregroundStyle(Color(red: 0.78, green: 0.58, blue: 0.17))
                Text("Grow your kingdom.").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("The biggest patch gets the crown. Steal a loop to take the lead.")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).lineSpacing(4).foregroundStyle(Color.moss)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.95, green: 0.91, blue: 0.79), in: RoundedRectangle(cornerRadius: 22))
        }.padding(.vertical, 16)
    }

    private var ranked: [Int] {
        (0..<session.scores.count).sorted {
            session.scores[$0] == session.scores[$1] ? $0 < $1 : session.scores[$0] > session.scores[$1]
        }
    }

    private func scoreRow(_ id: Int) -> some View {
        let fruit = session.engine?.players[id].fruit ?? .watermelon
        return HStack(spacing: 8) {
            FruitSticker(fruit: fruit).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(id == 0 ? "You" : fruit.name).font(.system(size: 13, weight: .bold, design: .rounded))
                    if session.leader == id { Image(systemName: "crown.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                }
                Text(id == 0 ? "Little land collector" : "Fruit rival").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Color.moss)
            }
            Spacer(minLength: 0)
            Text("\(percentage(id), specifier: "%.1f")%")
                .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
        }.padding(10).background(id == 0 ? Color.white : Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }

    private var compactScores: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(0..<4) { id in
                    HStack(spacing: 4) {
                        Text(session.engine?.players[id].fruit.emoji ?? "🍉")
                        Text("\(percentage(id), specifier: "%.1f")%")
                        if session.leader == id { Image(systemName: "crown.fill").foregroundStyle(.orange) }
                    }.font(.system(size: 12, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
                }
            }
            ProgressView(value: session.allocated).tint(Color.moss).accessibilityLabel("Island claimed")
        }
    }

    private func percentage(_ id: Int) -> Double {
        Double(session.scores[id]) * 100 / Double(max(session.engine?.land.count ?? 1, 1))
    }

    private func directionButtons(_ scene: GameScene) -> some View {
        HStack(spacing: 6) {
            directionButton(.left, symbol: "arrow.left", scene: scene)
            VStack(spacing: 4) {
                directionButton(.up, symbol: "arrow.up", scene: scene)
                directionButton(.down, symbol: "arrow.down", scene: scene)
            }
            directionButton(.right, symbol: "arrow.right", scene: scene)
        }
    }

    private func directionButton(_ direction: Direction, symbol: String, scene: GameScene) -> some View {
        Button {
            guard !scene.frozen else { return }
            scene.engine.move(scene.engine.players[0], to: scene.engine.players[0].position.moved(direction))
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                .frame(width: 44, height: 44).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !scene.frozen { scene.steering = direction } }
                .onEnded { _ in scene.steering = nil })
            .accessibilityLabel("Move \(symbol.replacingOccurrences(of: "arrow.", with: ""))")
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .frame(width: 44, height: 44).background(.white.opacity(0.8), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var pauseOverlay: some View {
        overlay {
            VStack(spacing: 20) {
                Text("A little breather.").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Your island can wait.").foregroundStyle(Color.moss)
                Toggle("Gentle haptics", isOn: $session.haptics).tint(Color.moss)
                    .onChange(of: session.haptics) { _, enabled in session.scene?.haptics = enabled }
                primaryButton("Back to growing") { session.setPaused(false) }
                Button("Start this island over") { session.start(level: session.level) }.fontWeight(.semibold)
                Button("Back to the garden") { session.menu() }.foregroundStyle(Color.moss)
            }
        }
    }

    private var resultsOverlay: some View {
        overlay {
            VStack(spacing: 17) {
                Image(systemName: "crown.fill").font(.system(size: 45)).foregroundStyle(.orange)
                Text(session.leader == 0 ? "A fruitful victory!" : "A lovely little harvest.")
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                Text("Every patch has a home. You claimed \(percentage(0), specifier: "%.1f")% of the island.")
                    .font(.system(size: 15, weight: .medium, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(Color.moss)
                VStack(spacing: 6) { ForEach(ranked, id: \.self) { id in scoreRow(id) } }
                primaryButton("A fresh island →") { session.start(level: session.level + 1) }
                Button("Back to the garden") { session.menu() }.foregroundStyle(Color.moss)
            }
        }
    }

    private func overlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.ink.opacity(0.32).ignoresSafeArea()
            content().padding(32).frame(maxWidth: 420)
                .background(Color.paper, in: RoundedRectangle(cornerRadius: 30))
                .shadow(color: Color.ink.opacity(0.12), radius: 30, y: 10)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity).padding(18)
                .foregroundStyle(.white).background(Color.ink, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }

    private var help: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Little loops.\nBig possibilities.").font(.system(size: 36, weight: .heavy, design: .rounded))
                    helpRow("hand.draw.fill", "1. Find your feet", "Touch anywhere on the island and drag in a direction. Keep your finger down to move; lift it to stop. The arrow buttons work too.")
                    helpRow("point.topleft.down.to.point.bottomright.curvepath", "2. Make a loop", "Leave your colored patch to draw a seed trail. Return to your territory to claim the trail and everything enclosed—even another fruit's land.")
                    helpRow("scissors", "3. Protect your trail", "Cross a rival's exposed trail to snip it. If yours gets cut, or you cross your own trail, you return home. Your existing land stays yours.")
                    helpRow("crown.fill", "4. Wear the crown", "The fruit with the most land wears the crown. The round ends only when 100% of the island is claimed. The biggest kingdom wins; ties favor You, then the listed rival order.")
                    Text("Each fresh island is a new organic shape on the same-sized canvas. This prototype is an offline game with three computer-controlled rivals.")
                        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Color.moss)
                }.padding(30)
            }.background(Color.paper)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { session.setHelp(false) }.tint(Color.ink) } }
        }.presentationDetents([.large])
    }

    private func helpRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Color.moss).frame(width: 30)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 15, weight: .medium, design: .rounded)).lineSpacing(4).foregroundStyle(Color.moss)
            }
        }
    }
}

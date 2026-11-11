import SwiftUI

struct MelonWedge: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15), control: CGPoint(x: rect.minX, y: rect.maxY))
        }
    }
}

struct FruitSticker: View {
    let fruit: Fruit
    var body: some View {
        GeometryReader { geometry in
            let w = min(geometry.size.width, geometry.size.height)
            ZStack {
                if fruit == .watermelon {
                    MelonWedge().fill(Color(fruit.color))
                        .overlay(MelonWedge().stroke(Color(fruit.darkColor), lineWidth: w * 0.07))
                    ForEach(0..<3) { i in
                        Ellipse().fill(Color.ink).frame(width: w * 0.035, height: w * 0.075)
                            .offset(x: CGFloat(i - 1) * w * 0.22, y: -w * 0.14)
                    }
                } else {
                    Circle().fill(Color(fruit.color)).overlay(Circle().stroke(Color(fruit.darkColor), lineWidth: w * 0.04))
                    Ellipse().fill(Color.moss).frame(width: w * 0.28, height: w * 0.13)
                        .rotationEffect(.degrees(-30)).offset(x: w * 0.15, y: -w * 0.48)
                    if fruit == .kiwi {
                        Circle().fill(Color.paper.opacity(0.5)).frame(width: w * 0.45, height: w * 0.45)
                    }
                }
                HStack(spacing: w * 0.24) {
                    Circle().frame(width: w * 0.055, height: w * 0.055)
                    Circle().frame(width: w * 0.055, height: w * 0.055)
                }.foregroundStyle(Color.ink).offset(y: w * 0.04)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.45, y: w * 0.64))
                    p.addQuadCurve(to: CGPoint(x: w * 0.55, y: w * 0.64), control: CGPoint(x: w * 0.5, y: w * 0.71))
                }.stroke(Color.ink, style: StrokeStyle(lineWidth: max(1, w * 0.025), lineCap: .round))
                HStack(spacing: w * 0.49) {
                    Ellipse().frame(width: w * 0.13, height: w * 0.065)
                    Ellipse().frame(width: w * 0.13, height: w * 0.065)
                }.foregroundStyle(Color.pink.opacity(0.4)).offset(y: w * 0.16)
            }.frame(width: w * 0.85, height: w * 0.85).frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
}

struct IslandIllustration: View {
    let fruit: Fruit
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Canvas { context, size in
                    let island = Path { p in
                        p.move(to: CGPoint(x: size.width * 0.17, y: size.height * 0.26))
                        p.addCurve(to: CGPoint(x: size.width * 0.79, y: size.height * 0.14), control1: CGPoint(x: size.width * 0.29, y: -size.height * 0.04), control2: CGPoint(x: size.width * 0.62, y: size.height * 0.23))
                        p.addCurve(to: CGPoint(x: size.width * 0.85, y: size.height * 0.72), control1: CGPoint(x: size.width * 1.05, y: size.height * 0.04), control2: CGPoint(x: size.width * 0.95, y: size.height * 0.5))
                        p.addCurve(to: CGPoint(x: size.width * 0.24, y: size.height * 0.89), control1: CGPoint(x: size.width * 0.91, y: size.height * 1.06), control2: CGPoint(x: size.width * 0.45, y: size.height * 0.76))
                        p.addCurve(to: CGPoint(x: size.width * 0.17, y: size.height * 0.26), control1: CGPoint(x: -size.width * 0.06, y: size.height * 1.05), control2: CGPoint(x: size.width * 0.11, y: size.height * 0.53))
                    }
                    context.fill(island.offsetBy(dx: 0, dy: 8), with: .color(Color.ink.opacity(0.1)))
                    context.fill(island, with: .color(Color(red: 0.92, green: 0.93, blue: 0.85)))
                    context.stroke(island, with: .color(.white), lineWidth: 5)
                    context.clip(to: island)
                    let patches: [(CGRect, Fruit)] = [
                        (CGRect(x: size.width * 0.05, y: size.height * 0.48, width: size.width * 0.52, height: size.height * 0.5), fruit),
                        (CGRect(x: size.width * 0.56, y: 0, width: size.width * 0.5, height: size.height * 0.38), .orange),
                        (CGRect(x: size.width * 0.7, y: size.height * 0.62, width: size.width * 0.4, height: size.height * 0.3), .blueberry)
                    ]
                    for (rect, fruit) in patches { context.fill(Path(roundedRect: rect, cornerRadius: 18), with: .color(Color(fruit.color))) }
                    for x in stride(from: 12.0, to: size.width, by: 22) {
                        for y in stride(from: 12.0, to: size.height, by: 22) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 3)), with: .color(Color.ink.opacity(0.18)))
                        }
                    }
                    let trail = Path { p in
                        p.move(to: CGPoint(x: size.width * 0.4, y: size.height * 0.64))
                        p.addLine(to: CGPoint(x: size.width * 0.4, y: size.height * 0.34))
                        p.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.34))
                        p.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.59))
                    }
                    context.stroke(trail, with: .color(Color(fruit.darkColor)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 10]))
                }
                FruitSticker(fruit: fruit).frame(width: w * 0.23, height: w * 0.23)
                    .rotationEffect(.degrees(-8)).position(x: w * 0.64, y: h * 0.59)
                Image(systemName: "crown.fill").font(.system(size: w * 0.08)).foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.2))
                    .rotationEffect(.degrees(8)).position(x: w * 0.65, y: h * 0.41)
                FruitSticker(fruit: .orange).frame(width: w * 0.13, height: w * 0.13).position(x: w * 0.77, y: h * 0.23)
                Text("a patch of possibility").font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1)
                    .foregroundStyle(Color.moss).rotationEffect(.degrees(-6)).position(x: w * 0.52, y: h * 0.98)
            }
        }.accessibilityHidden(true)
    }
}

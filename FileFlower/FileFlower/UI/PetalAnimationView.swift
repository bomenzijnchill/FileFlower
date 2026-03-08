import SwiftUI

/// Bloemblaadje-vorm via quadratic curves
private struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: h),
            control: CGPoint(x: w * 1.3, y: h * 0.4)
        )
        path.addQuadCurve(
            to: CGPoint(x: w / 2, y: 0),
            control: CGPoint(x: -w * 0.3, y: h * 0.4)
        )
        return path
    }
}

/// Individueel bloemblaadje met gerandomiseerde animatie-properties
private struct Petal: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let angle: Double
    let xOffset: CGFloat
    let yOffset: CGFloat
    let delay: Double
    let rotationSpeed: Double
    let scaleEnd: CGFloat
}

/// Animatieview die bloemblaadjes omhoog laat vliegen vanuit een centraal punt.
/// Volledig zelfstandig — triggert animatie bij onAppear en verdwijnt vanzelf.
struct PetalAnimationView: View {
    @State private var animate = false

    private let petals: [Petal] = (0..<10).map { _ in
        Petal(
            color: [.brandPowderBlush, .petalRosePink, .petalLavender, .brandBurntPeach].randomElement()!,
            size: CGFloat.random(in: 8...14),
            angle: Double.random(in: 0...360),
            xOffset: CGFloat.random(in: -50...50),
            yOffset: CGFloat.random(in: -140...(-80)),
            delay: Double.random(in: 0...0.3),
            rotationSpeed: Double.random(in: 90...360),
            scaleEnd: CGFloat.random(in: 0.2...0.5)
        )
    }

    var body: some View {
        ZStack {
            ForEach(petals) { petal in
                PetalShape()
                    .fill(petal.color)
                    .frame(width: petal.size, height: petal.size * 1.6)
                    .rotationEffect(.degrees(animate ? petal.angle + petal.rotationSpeed : petal.angle))
                    .offset(
                        x: animate ? petal.xOffset : 0,
                        y: animate ? petal.yOffset : 0
                    )
                    .scaleEffect(animate ? petal.scaleEnd : 1.0)
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.5).delay(petal.delay),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

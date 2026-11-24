import SwiftUI

struct AnimatedBackground: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.03, blue: 0.12),
                                        Color(red: 0.09, green: 0.05, blue: 0.24)],
                               startPoint: .top, endPoint: .bottom)
                blob(.indigo, x: sin(t * 0.30) * 120, y: cos(t * 0.25) * 200 - 100, size: 320)
                blob(.purple, x: cos(t * 0.22) * 140, y: sin(t * 0.28) * 220 + 120, size: 300)
                blob(.cyan,   x: sin(t * 0.18 + 2) * 160, y: cos(t * 0.20 + 1) * 180, size: 230)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ c: Color, x: Double, y: Double, size: CGFloat) -> some View {
        Circle().fill(c.opacity(0.45)).frame(width: size, height: size)
            .blur(radius: 80).offset(x: x, y: y)
    }
}

struct OrbView: View {
    var size: CGFloat
    var busy: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [.cyan, .indigo, .purple, .pink, .cyan], center: .center))
                .blur(radius: size * 0.10)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle().fill(.ultraThinMaterial).padding(size * 0.08)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: busy)
        }
        .frame(width: size, height: size)
        .scaleEffect(busy ? 1.12 : 1)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: busy)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle().fill(.white.opacity(0.8)).frame(width: 8, height: 8)
                    .scaleEffect(on ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { on = true }
    }
}

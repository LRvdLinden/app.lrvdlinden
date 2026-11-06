import SwiftUI

/// Splashscreen: het LR Beheer-logo verschijnt met een korte veer, de blauwe stip pulseert één keer en de zes
/// omgevingen lichten kort op. Totaal ±1 seconde; wacht nooit op het netwerk. De statische launch screen ervoor heeft
/// dezelfde achtergrondkleur (LaunchBackground), zodat de overgang naadloos is.
struct SplashView: View {
    let done: () -> Void
    @State private var logoIn = false
    @State private var ring = false
    @State private var dots = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Brand.logoDot.opacity(ring ? 0 : 0.55), lineWidth: 2)
                        .frame(width: ring ? 220 : 120, height: ring ? 220 : 120)
                    BeheerMark(size: 112)
                        .scaleEffect(logoIn ? 1 : 0.82)
                        .opacity(logoIn ? 1 : 0)
                }
                VStack(spacing: 6) {
                    Text(verbatim: "LR Beheer")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Al je platformen op één plek")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .opacity(logoIn ? 1 : 0)
                .offset(y: logoIn ? 0 : 8)
                HStack(spacing: 8) {
                    ForEach(Array(BeheerEnvironment.allCases.enumerated()), id: \.element) { i, env in
                        Circle()
                            .fill(env.color)
                            .frame(width: 7, height: 7)
                            .opacity(dots ? 1 : 0.15)
                            .animation(.easeOut(duration: 0.25).delay(reduceMotion ? 0 : 0.35 + Double(i) * 0.05), value: dots)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LR Beheer")
        .task {
            if reduceMotion {
                logoIn = true; dots = true
                try? await Task.sleep(for: .seconds(0.4))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { logoIn = true }
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) { ring = true }
                dots = true
                try? await Task.sleep(for: .seconds(1.0))
            }
            done()
        }
    }
}

/// Het LR Beheer-merk: de LR-tegel van lrvdlinden.app met een klein "beheer"-raster (vier vlakjes = meerdere
/// omgevingen) rechtsonder. Zelfde ontwerp als het app-icoon (tools/make_icon.py).
struct BeheerMark: View {
    var size: CGFloat = 60

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LRLogo(size: size)
            Canvas { ctx, canvas in
                let s = canvas.width
                let gap = s * 0.08, cell = (s - gap) / 2
                for r in 0..<2 {
                    for c in 0..<2 {
                        let rect = CGRect(x: CGFloat(c) * (cell + gap), y: CGFloat(r) * (cell + gap), width: cell, height: cell)
                        let color: Color = (r == 1 && c == 1) ? Brand.logoDot : .white.opacity(r == 0 && c == 0 ? 0.95 : 0.55)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.28), with: .color(color))
                    }
                }
            }
            .frame(width: size * 0.26, height: size * 0.26)
            .padding(size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

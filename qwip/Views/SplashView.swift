import SwiftUI

// Fixed brand colors for the splash — these never change with color scheme.
private let splashGreen = Color(red: 31/255, green: 61/255, blue: 50/255)
private let splashCream = Color(red: 253/255, green: 251/255, blue: 247/255)

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var dotPhase: Bool = false
    @State private var orb1Scale: CGFloat = 0.5
    @State private var orb2Scale: CGFloat = 0.3

    var body: some View {
        ZStack {
            splashGreen.ignoresSafeArea()

            // Background glass orbs (chaos decoration)
            Circle()
                .fill(splashCream.opacity(0.06))
                .frame(width: 280)
                .offset(x: -100, y: -200)
                .blur(radius: 30)
                .scaleEffect(orb1Scale)

            Circle()
                .fill(splashCream.opacity(0.08))
                .frame(width: 200)
                .offset(x: 120, y: 180)
                .blur(radius: 20)
                .scaleEffect(orb2Scale)

            Circle()
                .fill(splashCream.opacity(0.04))
                .frame(width: 120)
                .offset(x: 140, y: -280)
                .blur(radius: 16)

            VStack(spacing: 0) {
                Spacer()

                // Logo + wordmark
                VStack(spacing: 16) {
                    Text("qwip")
                        .font(.funnelDisplay(58, weight: .bold))
                        .foregroundStyle(splashCream)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // Tagline
                VStack(spacing: 2) {
                    Text("work your way,")
                        .font(.funnelDisplay(16, weight: .bold))
                        .foregroundStyle(splashCream.opacity(0.55))
                    Text("anywhere")
                        .font(.cormorantGaramond(18))
                        .italic()
                        .foregroundStyle(splashCream.opacity(0.55))
                }
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .opacity(taglineOpacity)

                Spacer()

                // Loading indicator — bold pulsing dots
                HStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(splashCream.opacity(dotPhase ? 0.65 : 0.25))
                            .frame(width: dotPhase && i == 1 ? 20 : 8, height: 6)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.65)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: dotPhase
                            )
                    }
                }
                .opacity(taglineOpacity)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                logoScale = 1.0
                logoOpacity = 1.0
                orb1Scale = 1.0
                orb2Scale = 1.0
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.5)) {
                taglineOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                dotPhase = true
            }
        }
    }
}

#Preview {
    SplashView()
}

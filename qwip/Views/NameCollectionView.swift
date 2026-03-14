import SwiftUI

struct NameCollectionView: View {
    @Environment(AuthService.self) private var authService

    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 320)
                .offset(x: -80, y: -340)
                .blur(radius: 40)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    VStack(spacing: 8) {
                        Text("qwip")
                            .font(.funnelDisplay(56, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)

                        VStack(spacing: 2) {
                            Text("one last thing,")
                                .font(.funnelDisplay(18, weight: .bold))
                            Text("what's your name?")
                                .font(.cormorantGaramond(21))
                                .italic()
                        }
                        .foregroundColor(Color.brandPrimary.opacity(0.5))
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 100)
                    .padding(.bottom, 44)

                    VStack(spacing: 10) {
                        TextField("Your name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($nameFocused)
                            .font(.dmSans(15, weight: .medium))
                            .foregroundStyle(Color.brandPrimary)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.brandPrimary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.brandPrimary.opacity(nameFocused ? 0.3 : 0.12), lineWidth: 1.5)
                                    )
                            )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.dmSans(13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: { Task { await submit() } }) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(Color.brandSecondary)
                                } else {
                                    HStack(spacing: 8) {
                                        Text("Continue")
                                            .font(.dmSans(15, weight: .black))
                                            .tracking(0.3)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundStyle(Color.brandSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.7 : 1)
                    }
                    .padding(20)
                    .background(glassBackground(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { nameFocused = true }
    }

    private func submit() async {
        nameFocused = false
        isLoading = true
        errorMessage = nil
        do {
            try await authService.updateDisplayName(name.trimmingCharacters(in: .whitespaces))
            // authService.needsDisplayName becomes false → RootView transitions to ContentView
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

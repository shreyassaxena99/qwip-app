import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var authService
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if authService.needsDisplayName {
                NameCollectionView()
                    .transition(.opacity)
                    .zIndex(1)
            } else if authService.isAuthenticated {
                ContentView()
                    .environment(\.signOut) {
                        // signOut environment key type is () -> Void (synchronous).
                        // We spawn a Task and use try? to satisfy that type.
                        // On failure: authStateChanges won't fire, session stays set,
                        // user stays logged in. This is acceptable — sign-out failures
                        // are rare (network is not required for local session clearing
                        // in Supabase SDK) and a retry is as simple as tapping again.
                        Task { try? await authService.signOut() }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                SignInView()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showSplash)
        .animation(.easeInOut(duration: 0.45), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.45), value: authService.needsDisplayName)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                showSplash = false
            }
        }
    }
}

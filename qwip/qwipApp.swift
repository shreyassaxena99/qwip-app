import SwiftUI
import CoreText
import GoogleSignIn

@main
struct qwipApp: App {

    @State private var authService = AuthService()

    init() {
        // Font registration
        let fontFiles = [
            "FunnelDisplay-Regular.ttf",
            "FunnelDisplay-Bold.ttf",
            "CormorantGaramond-Italic.ttf",
            "CormorantGaramond-LightItalic.ttf",
            "DMSans-VariableFont_opsz,wght.ttf"
        ]
        for file in fontFiles {
            if let url = Bundle.main.url(forResource: file, withExtension: nil) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        // Tab bar appearance
        let normalColor  = UIColor(Color.brandSecondary.opacity(0.45))
        let selectedColor = UIColor(Color.brandSecondary)

        let item = UITabBarItemAppearance()
        item.normal.iconColor = normalColor
        item.normal.titleTextAttributes   = [.foregroundColor: normalColor]
        item.selected.iconColor = selectedColor
        item.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Color.brandPrimary)
        bar.stackedLayoutAppearance       = item
        bar.inlineLayoutAppearance        = item
        bar.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance    = bar
        UITabBar.appearance().scrollEdgeAppearance  = bar

        // Required by GoogleSignIn-iOS v7+ — must be set before the first sign-in attempt.
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Config.googleIOSClientID)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .task {
                    await authService.restoreSession()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

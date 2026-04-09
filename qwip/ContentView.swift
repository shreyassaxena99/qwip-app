import SwiftUI

struct ContentView: View {
    init() {
        // iOS 26's glass tab bar uses .tint() for the selected pill highlight and
        // renders the icon/text as a contrasting black or white — wrong for our palette.
        // Setting tintColor directly on UITabBar.appearance() (without touching
        // standardAppearance) fixes the icon/text color while leaving glass intact.
        let tint = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xC9/255, green: 0xB8/255, blue: 0xE0/255, alpha: 1) // lavender
                : UIColor(red: 0x1F/255, green: 0x3D/255, blue: 0x32/255, alpha: 1) // brandPrimary
        }
        UITabBar.appearance().tintColor = tint
    }

    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var savedSpotService = SavedSpotService()
    @State private var collectionService = CollectionService()
    @State private var selectedTab = 0
    @State private var searchViewModel = SearchViewModel()
    @Environment(AppRouter.self) var appRouter
    @AppStorage("appTheme") private var appTheme = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Map", systemImage: "map.fill", value: 0) {
                MapView()
            }
            Tab("Saved", systemImage: "heart.fill", value: 1) {
                CollectionsView()
            }
            Tab("Profile", systemImage: "person.fill", value: 2) {
                ProfileView()
            }
        }
        .preferredColorScheme(appTheme == "dark" ? .dark : appTheme == "light" ? .light : nil)
        .environment(store)
        .environment(locationService)
        .environment(savedSpotService)
        .environment(collectionService)
        .environment(searchViewModel)
        .task {
            async let s: () = savedSpotService.load()
            async let c: () = collectionService.load()
            _ = await (s, c)
        }
        .onChange(of: appRouter.pendingCollectionId) { _, id in
            if id != nil { selectedTab = 1 }
        }
        .onChange(of: searchViewModel.selectedRadius) { _, radius in
            if radius != nil { selectedTab = 0 }
        }
    }
}

#Preview {
    ContentView()
}

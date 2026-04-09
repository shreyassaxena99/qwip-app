import SwiftUI

struct ContentView: View {
    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var savedSpotService = SavedSpotService()
    @State private var collectionService = CollectionService()
    @State private var selectedTab = 0
    @State private var searchViewModel = SearchViewModel()
    @Environment(AppRouter.self) var appRouter
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appTheme = "system"

    private var tabTint: Color {
        colorScheme == .dark
            ? Color(red: 0xC9/255, green: 0xB8/255, blue: 0xE0/255) // lavender
            : Color(red: 0x1F/255, green: 0x3D/255, blue: 0x32/255) // brandPrimary
    }

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
        .tint(tabTint)
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

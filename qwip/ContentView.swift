import SwiftUI

struct ContentView: View {
    init() {
        let item = UITabBarItemAppearance(style: .stacked)
        item.selected.iconColor = .label
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.label]

        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var savedSpotService = SavedSpotService()
    @State private var collectionService = CollectionService()
    @State private var selectedTab = 0
    @State private var searchViewModel = SearchViewModel()
    @Environment(AppRouter.self) var appRouter

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
            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                EmptyView()
            }
        }
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
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }
            if new == 3 {
                // Intercept search bubble tap: go to Map and open overlay
                selectedTab = 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    searchViewModel.isSearchActive = true
                }
            } else if old != 3 && searchViewModel.isSearchActive {
                // Navigated to another tab while search was open — dismiss
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchViewModel.clearSearch()
                }
            }
        }
        .onChange(of: searchViewModel.selectedRadius) { _, radius in
            if radius != nil { selectedTab = 0 }
        }
    }
}

#Preview {
    ContentView()
}

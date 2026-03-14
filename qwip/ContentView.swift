import SwiftUI

struct ContentView: View {
    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: MapView()
                case 1: SavedSpotsView()
                default: ProfileView()
                }
            }
            .environment(store)
            .environment(locationService)

            GlassTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Floating Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 4) {
            TabPill(icon: "map.fill", label: "Map", isSelected: selectedTab == 0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    selectedTab = 0
                }
            }
            TabPill(icon: "heart.fill", label: "Saved", isSelected: selectedTab == 1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    selectedTab = 1
                }
            }
            TabPill(icon: "person.fill", label: "Profile", isSelected: selectedTab == 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    selectedTab = 2
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.brandPrimary.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.brandPrimary.opacity(0.22), Color.brandPrimary.opacity(0.07)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.brandPrimary.opacity(0.15), radius: 24, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .clipShape(Capsule())
        .padding(.horizontal, 48)
        .padding(.bottom, 28)
    }
}

private struct TabPill: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                if isSelected {
                    Text(label)
                        .font(.dmSans(12, weight: .black))
                        .tracking(0.2)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .foregroundStyle(isSelected ? Color.brandSecondary : Color.brandPrimary.opacity(0.45))
            .padding(.horizontal, isSelected ? 18 : 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.brandPrimary : Color.clear)
                    .shadow(color: isSelected ? Color.brandPrimary.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

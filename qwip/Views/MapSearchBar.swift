import SwiftUI
import MapKit
import CoreLocation

// MARK: - Map Search Bar

struct MapSearchBar: View {
    @Environment(SearchViewModel.self) var searchViewModel
    @Environment(LocationService.self) var locationService
    @FocusState private var searchFocused: Bool

    private var searchRegion: MKCoordinateRegion {
        let center = locationService.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        return MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if searchViewModel.isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: searchViewModel.isExpanded) { _, expanded in
            searchFocused = expanded
        }
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    searchViewModel.isExpanded = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Search")
                        .font(.dmSans(11, weight: .black))
                        .tracking(0.3)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
        }
    }

    // MARK: Expanded

    private var expandedContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                TextField("Search places, streets, postcodes…", text: Binding(
                    get: { searchViewModel.query },
                    set: { searchViewModel.updateQuery($0, region: searchRegion) }
                ))
                .font(.dmSans(14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                if searchViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(Color.primary.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )

            Button("Cancel") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    searchViewModel.clearSearch()
                }
            }
            .font(.dmSans(14, weight: .semibold))
            .foregroundStyle(Color.primary)
        }
    }
}

// MARK: - Search Results Card

struct SearchResultsCard: View {
    @Environment(SearchViewModel.self) var searchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(searchViewModel.results) { place in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            searchViewModel.selectPlace(place)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.dmSans(13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                if !place.formattedAddress.isEmpty {
                                    Text(place.formattedAddress)
                                        .font(.dmSans(11))
                                        .foregroundStyle(Color.primary.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if place.id != searchViewModel.results.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.07))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - Radius Picker Card

struct RadiusPickerCard: View {
    @Environment(SearchViewModel.self) var searchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let place = searchViewModel.selectedPlace {
                Text("Spots near \(place.name)")
                    .font(.dmSans(12, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                ForEach(SearchViewModel.radiusOptions, id: \.metres) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            searchViewModel.selectRadius(option.metres)
                        }
                    } label: {
                        Text(option.label)
                            .font(.dmSans(13, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

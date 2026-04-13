import SwiftUI
import MapKit
import CoreLocation

struct SearchOverlay: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LocationService.self) private var locationService
    @FocusState private var inputFocused: Bool
    @State private var panelVisible = false

    private var searchRegion: MKCoordinateRegion {
        let center = locationService.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Frost background — tap to dismiss
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.clearSearch()
                    }
                }

            // Content column — does not dismiss on tap
            VStack(alignment: .leading, spacing: 12) {
                topPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if searchViewModel.selectedPlace == nil {
                    if !searchViewModel.results.isEmpty || searchViewModel.isSearching {
                        resultsCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else {
                    radiusCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()
            }
            .offset(y: panelVisible ? 0 : -40)
            .opacity(panelVisible ? 1 : 0)
        }
        .onAppear {
            // Defer to next runloop to escape any active tab-switch animation transaction,
            // otherwise the spring animation gets swallowed and the panel stays invisible.
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    panelVisible = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                inputFocused = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.results.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.selectedPlace?.id)
    }

    // MARK: - Top Panel

    @ViewBuilder
    private var topPanel: some View {
        if let place = searchViewModel.selectedPlace {
            // Step 2: selected place name + Edit button
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spots near")
                        .font(.dmSans(13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.5))
                    Text(place.name)
                        .font(.dmSans(28, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.editPlace()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        inputFocused = true
                    }
                } label: {
                    Text("Edit")
                        .font(.dmSans(14, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.brandPrimary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
        } else {
            // Step 1: large text input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.4))

                TextField("Where do you want to work?", text: Binding(
                    get: { searchViewModel.query },
                    set: { searchViewModel.updateQuery($0, region: searchRegion) }
                ))
                .font(.dmSans(22, weight: .semibold))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($inputFocused)

                if searchViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.primary.opacity(0.4))
                } else if !searchViewModel.query.isEmpty {
                    Button {
                        searchViewModel.updateQuery("", region: searchRegion)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                // Dismiss button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.clearSearch()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
        }
    }

    // MARK: - Results Card

    private var resultsCard: some View {
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
                                    .font(.dmSans(14, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                if !place.formattedAddress.isEmpty {
                                    Text(place.formattedAddress)
                                        .font(.dmSans(12))
                                        .foregroundStyle(Color.primary.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if place.id != searchViewModel.results.last?.id {
                        Divider()
                            .overlay(Color.brandBorder)
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())  // prevent tap-through to dismiss layer
    }

    // MARK: - Radius Card

    private var radiusCard: some View {
        SearchRadiusCard()
            .padding(.horizontal, 16)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
    }
}

// MARK: - Radius Card Component

private struct SearchRadiusCard: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @State private var sliderIndex: Double = 0

    private let options = SearchViewModel.radiusOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search radius")
                .font(.dmSans(13, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.55))
                .padding(.horizontal, 16)

            VStack(spacing: 4) {
                Slider(value: $sliderIndex, in: 0...Double(options.count - 1), step: 1)
                    .tint(Color.brandPrimary)
                    .padding(.horizontal, 16)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Text(option.label)
                            .font(.dmSans(10, weight: .semibold))
                            .foregroundStyle(
                                Int(sliderIndex.rounded()) == index
                                    ? Color.primary
                                    : Color.primary.opacity(0.35)
                            )
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: sliderIndex)
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                let index = Int(sliderIndex.rounded())
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    searchViewModel.selectRadius(options[index].metres)
                }
            } label: {
                Text("Done")
                    .font(.dmSans(14, weight: .black))
                    .tracking(0.3)
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

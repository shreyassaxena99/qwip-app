import Foundation
import MapKit
import Observation

@Observable
final class SearchViewModel {
    var query: String = ""
    var results: [Place] = []
    var isSearching: Bool = false
    var isSearchActive: Bool = false
    var selectedPlace: Place? = nil
    var selectedRadius: Double? = nil  // metres

    static let radiusOptions: [(label: String, metres: Double)] = [
        ("¼ mi", 402),
        ("½ mi", 805),
        ("1 mi", 1609),
        ("3 mi", 4828)
    ]

    private var searchTask: Task<Void, Never>? = nil

    /// Call on every keystroke. Cancels any in-flight search and debounces 300 ms.
    func updateQuery(_ newQuery: String, region: MKCoordinateRegion) {
        query = newQuery
        searchTask?.cancel()
        guard !newQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search(query: newQuery, region: region)
        }
    }

    @MainActor
    private func search(query: String, region: MKCoordinateRegion) async {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map { Place(from: $0) }
        } catch {
            results = []
        }
        isSearching = false
    }

    func selectPlace(_ place: Place) {
        selectedPlace = place
        selectedRadius = nil
        results = []
        query = ""
    }

    /// Resets back to the location input step, keeping isSearchActive true.
    func editPlace() {
        selectedPlace = nil
        selectedRadius = nil
        results = []
        query = ""
    }

    func selectRadius(_ metres: Double) {
        selectedRadius = metres
        isSearchActive = false
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        isSearchActive = false
        selectedPlace = nil
        selectedRadius = nil
    }
}

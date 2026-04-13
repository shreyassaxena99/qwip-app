import Foundation
import MapKit
import Contacts

struct Place: Identifiable {
    let id: UUID
    let name: String
    let formattedAddress: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem

    init(from mapItem: MKMapItem) {
        self.id = UUID()
        self.name = mapItem.name ?? "Unknown"
        self.coordinate = mapItem.placemark.coordinate
        self.mapItem = mapItem

        if let postalAddress = mapItem.placemark.postalAddress {
            let raw = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            self.formattedAddress = raw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } else {
            self.formattedAddress = ""
        }
    }
}

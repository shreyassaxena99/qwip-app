import Foundation
import Observation

@Observable
final class AppRouter {
    var pendingCollectionId: String? = nil
    var pendingSharedCollectionId: String? = nil

    /// Extracts a collection ID from a Universal Link URL.
    /// Returns nil for Google OAuth callbacks or any unrecognised URL.
    static func collectionId(from url: URL) -> String? {
        guard url.scheme == "https",
              url.host == "qwip.co.uk" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2,
              components[0] == "collections",
              !components[1].isEmpty else { return nil }
        return components[1]
    }
}

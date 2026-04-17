import Foundation

enum AnalyticsConsentKey {
    static func storageKey(for userId: String) -> String {
        "analyticsConsent_\(userId)"
    }

    static func isDecided(for userId: String) -> Bool {
        UserDefaults.standard.object(forKey: storageKey(for: userId)) != nil
    }

    static func isAccepted(for userId: String) -> Bool {
        UserDefaults.standard.object(forKey: storageKey(for: userId)) as? Bool ?? false
    }

    static func record(accepted: Bool, for userId: String) {
        UserDefaults.standard.set(accepted, forKey: storageKey(for: userId))
    }

}

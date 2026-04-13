import SwiftUI

extension Font {
    static func funnelDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Funnel Display", size: size).weight(weight)
    }

    static func cormorantGaramond(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Cormorant Garamond", size: size).weight(weight)
    }

    static func dmSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("DM Sans", size: size).weight(weight)
    }
}

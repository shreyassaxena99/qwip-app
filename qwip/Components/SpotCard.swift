import SwiftUI

// MARK: - Spot Card (horizontal scroll carousel)

struct SpotCard: View {
    let spot: SpotPin

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Decorative blur orb
            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 90)
                .offset(x: 28, y: -18)
                .blur(radius: 10)

            VStack(alignment: .leading, spacing: 11) {
                // Category badge + open badge
                HStack(alignment: .center) {
                    Text(spot.category.displayName.uppercased())
                        .font(.dmSans(9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(Color.brandSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.brandPrimary)
                        .clipShape(Capsule())
                        .rotationEffect(.degrees(-1.5))
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: spot.category.systemIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }

                // Name
                Text(spot.name)
                    .font(.dmSans(15, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Rating
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(spot.formattedRating)
                        .font(.dmSans(18, weight: .black))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    Text("RATING")
                        .font(.dmSans(7.5, weight: .bold))
                        .foregroundStyle(Color.brandPrimary.opacity(0.4))
                        .tracking(0.5)
                }
            }
            .padding(14)
        }
        .frame(width: 186)
        .background(glassBackground(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.13), radius: 18, x: 0, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Spot Row (saved list)

struct SpotRow: View {
    let spot: SpotPin

    var body: some View {
        HStack(spacing: 14) {
            // Icon block
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.brandPrimary)
                    .frame(width: 52, height: 52)
                Image(systemName: spot.category.systemIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
            }
            .shadow(color: Color.brandPrimary.opacity(0.35), radius: 8, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(spot.name)
                        .font(.dmSans(15, weight: .heavy))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(spot.formattedRating)
                        .font(.dmSans(12, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                    Text("·")
                        .foregroundStyle(Color.brandPrimary.opacity(0.3))
                    Text(spot.category.displayName.uppercased())
                        .font(.dmSans(9, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                    if let address = spot.shortAddress {
                        Text("·")
                            .foregroundStyle(Color.brandPrimary.opacity(0.3))
                        Text(address)
                            .font(.dmSans(12))
                            .foregroundStyle(Color.brandPrimary.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.brandPrimary.opacity(0.25))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Open Badge

struct OpenBadge: View {
    let isOpen: Bool?

    var body: some View {
        if let isOpen {
            let fgColor = isOpen ? Color(hex: "1a7a50") : Color(hex: "c0392b")
            let bgColor = isOpen ? Color(hex: "d4f5e4") : Color(hex: "fde8e8")
            let label   = isOpen ? "OPEN" : "CLOSED"
            Text(label)
                .font(.dmSans(8, weight: .black))
                .tracking(0.6)
                .foregroundStyle(fgColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(bgColor)
                        .overlay(Capsule().stroke(fgColor.opacity(0.3), lineWidth: 1))
                )
        }
    }
}

// MARK: - Spot Annotation View

struct SpotAnnotationView: View {
    let spot: SpotPin
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Glow ring
                Circle()
                    .fill(
                        isSelected
                            ? Color.brandSecondary.opacity(0.35)
                            : Color.brandPrimary.opacity(0.2)
                    )
                    .frame(width: isSelected ? 56 : 44)
                    .blur(radius: 4)

                // Main circle
                Circle()
                    .fill(isSelected ? Color.brandSecondary : Color.brandPrimary)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(
                        color: isSelected ? Color.brandSecondary.opacity(0.5) : Color.brandPrimary.opacity(0.4),
                        radius: 6, x: 0, y: 2
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? Color.brandPrimary.opacity(0.3) : Color.brandSecondary.opacity(0.2),
                                lineWidth: 1.5
                            )
                    )

                Image(systemName: spot.category.systemIcon)
                    .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.brandSecondary)
            }
            PinPoint()
                .fill(isSelected ? Color.brandSecondary : Color.brandPrimary)
                .frame(width: 10, height: 6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

private struct PinPoint: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Glass background helper

func glassBackground(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.brandPrimary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.brandPrimary.opacity(0.22), Color.brandPrimary.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
}

// MARK: - Saved Spot Card (used in CollectionDetailView)

struct SavedSpotCard: View {
    let spot: SpotPin
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.brandPrimary.opacity(0.06))
                .frame(width: 70)
                .offset(x: 16, y: -16)
                .blur(radius: 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.brandPrimary)
                            .frame(width: 36, height: 36)
                        Image(systemName: spot.category.systemIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                    .shadow(color: Color.brandPrimary.opacity(0.35), radius: 6, x: 0, y: 2)
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }

                Text(spot.name)
                    .font(.dmSans(14, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(spot.category.displayName.uppercased())
                    .font(.dmSans(8.5, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(spot.formattedRating)
                        .font(.dmSans(13, weight: .black))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
            .padding(14)
        }
        .background(glassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.1), radius: 14, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

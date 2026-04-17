import SwiftUI

struct AnalyticsConsentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.07))
                    .frame(width: 80, height: 80)
                Image("ic_shield_check")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.brandPrimary)
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Help us improve qwip")
                    .font(.dmSans(22, weight: .black))
                    .foregroundStyle(Color.brandPrimary)
                    .multilineTextAlignment(.center)

                Text("We'd like to collect anonymous usage data — which spots you view, save, and share — to make the app better. No personal information is ever collected.")
                    .font(.dmSans(14))
                    .foregroundStyle(Color.brandPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    authService.recordAnalyticsConsent(accepted: true)
                } label: {
                    Text("Accept")
                        .font(.dmSans(15, weight: .black))
                        .tracking(0.3)
                        .foregroundStyle(Color.brandSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    authService.recordAnalyticsConsent(accepted: false)
                } label: {
                    Text("Decline")
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandSecondary.ignoresSafeArea())
    }
}

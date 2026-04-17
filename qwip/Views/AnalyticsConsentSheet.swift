import SwiftUI
import PostHog

struct AnalyticsConsentSheet: View {
    @AppStorage("analyticsConsentDecided") private var consentDecided = false
    @AppStorage("analyticsConsentAccepted") private var consentAccepted = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.brandPrimary.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 28) {
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
                    .padding(.top, 36)

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

                    VStack(spacing: 14) {
                        Button {
                            consentAccepted = true
                            consentDecided = true
                            PostHogSDK.shared.optIn()
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
                            consentAccepted = false
                            consentDecided = true
                            PostHogSDK.shared.optOut()
                        } label: {
                            Text("Decline")
                                .font(.dmSans(14))
                                .foregroundStyle(Color.brandPrimary.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, 28)
            }
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}

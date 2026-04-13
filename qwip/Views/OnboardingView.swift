import SwiftUI
import Supabase

struct OnboardingView: View {
    @Environment(AuthService.self) private var authService

    @State private var currentStep = 0
    @State private var workingStyle: String? = nil
    @State private var homeArea: String? = nil
    @State private var workArea: String? = nil
    @State private var isLoading = false

    @AppStorage("appTheme") private var colorSchemePreference = "system"

    private let totalSteps = 4

    private let workingStyles = [
        "Fully remote", "Office-based", "Freelance / self-employed", "Student", "Other"
    ]
    private let londonAreas = [
        "North London", "West London", "North West London", "East London",
        "South East London", "South West London", "Central London", "Outside London"
    ]
    private let appearanceOptions = ["Light", "Dark", "System default"]
    private let questions = [
        "How do you work?",
        "Where do you live in London?",
        "Where do you work in London?",
        "How would you like qwip to look?"
    ]

    private var currentOptions: [String] {
        switch currentStep {
        case 0: return workingStyles
        case 3: return appearanceOptions
        default: return londonAreas
        }
    }

    private var appearanceLabel: String {
        switch colorSchemePreference {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "System default"
        }
    }

    private var currentSelection: String? {
        switch currentStep {
        case 0: return workingStyle
        case 1: return homeArea
        case 2: return workArea
        case 3: return appearanceLabel
        default: return nil
        }
    }

    private func setSelection(_ value: String) {
        switch currentStep {
        case 0: workingStyle = (workingStyle == value) ? nil : value
        case 1: homeArea    = (homeArea == value)    ? nil : value
        case 2: workArea    = (workArea == value)    ? nil : value
        case 3:
            switch value {
            case "Light":          colorSchemePreference = "light"
            case "Dark":           colorSchemePreference = "dark"
            default:               colorSchemePreference = "system"
            }
        default: break
        }
    }

    private func advance() {
        if currentStep < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 }
        } else {
            Task { await submit() }
        }
    }

    private func skip() {
        switch currentStep {
        case 0: workingStyle = nil
        case 1: homeArea = nil
        case 2: workArea = nil
        default: break // appearance has a default, can't really skip
        }
        advance()
    }

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 320)
                .offset(x: -80, y: -340)
                .blur(radius: 40)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    progressBar
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentStep == 3 ? "PREFERENCES" : "ABOUT YOU")
                            .font(.dmSans(10, weight: .black))
                            .tracking(1.5)
                            .foregroundStyle(Color.brandPrimary.opacity(0.4))
                        Text(questions[currentStep])
                            .font(.dmSans(26, weight: .heavy))
                            .foregroundStyle(Color.brandPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if currentStep == 3 {
                            Text("You can change this anytime in Profile → Preferences.")
                                .font(.dmSans(13))
                                .foregroundStyle(Color.brandPrimary.opacity(0.45))
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                    optionsCard
                        .padding(.horizontal, 24)

                    actionButtons
                        .padding(.top, 16)
                        .padding(.horizontal, 24)

                    if currentStep < 3 {
                        Button(action: skip) {
                            Text("Skip this question")
                                .font(.dmSans(13, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary.opacity(0.4))
                        }
                        .padding(.top, 14)
                    }

                    if currentStep == 3 {
                        Text("Your other answers can be updated anytime in Profile → About You.")
                            .font(.dmSans(12))
                            .foregroundStyle(Color.brandPrimary.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 10) {
            Text("\(currentStep + 1) of \(totalSteps)")
                .font(.dmSans(11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.brandPrimary.opacity(0.4))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.brandBorder)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.brandPrimary)
                        .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Options Card

    private var optionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(currentOptions.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Divider()
                        .overlay(Color.brandBorder)
                }
                optionRow(option)
            }
        }
        .padding(.vertical, 4)
        .background(glassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
    }

    private func optionRow(_ option: String) -> some View {
        let selected = currentSelection == option
        return Button {
            setSelection(option)
        } label: {
            HStack {
                Text(option)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.clear : Color.brandBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? Color.brandPrimary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if currentStep > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep -= 1 }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1.5)
                            )
                            .frame(width: 48, height: 48)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brandPrimary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                advance()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.brandPrimary)
                        .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                    if isLoading {
                        ProgressView().tint(Color.brandSecondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(currentStep < totalSteps - 1 ? "Next" : "Finish")
                                .font(.dmSans(15, weight: .black))
                                .tracking(0.3)
                            Image(systemName: currentStep < totalSteps - 1 ? "arrow.right" : "checkmark")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.brandSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    // MARK: - Submit

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        if let session = authService.session {
            try? await UserProfileAPIClient.saveProfile(
                userId: session.user.id.uuidString,
                token: session.accessToken,
                workingStyle: workingStyle,
                homeArea: homeArea,
                workArea: workArea
            )
        }
        authService.completeOnboarding()
    }
}

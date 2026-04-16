import SwiftUI

struct SavedTourOverlay: View {
    @AppStorage("hasSeenSavedTour") private var hasSeenSavedTour = false

    var body: some View {
        ZStack {
            if !hasSeenSavedTour {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("🗂️")
                                .font(.system(size: 22))
                            Text("Collections")
                                .font(.dmSans(15, weight: .heavy))
                                .foregroundStyle(Color.brandSecondary)
                        }

                        Text("Group saved spots into themed collections — by area, vibe, or whatever works for you.")
                            .font(.dmSans(13))
                            .foregroundStyle(Color.brandSecondary.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) { hasSeenSavedTour = true }
                            } label: {
                                Text("Got it ✓")
                                    .font(.dmSans(13, weight: .black))
                                    .foregroundStyle(Color.brandPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.brandSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.3), radius: 16, x: 0, y: 6)
                    .padding(.horizontal, 24)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasSeenSavedTour)
    }
}

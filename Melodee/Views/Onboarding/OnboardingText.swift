import SwiftUI

struct OnboardingText: View {
    let feature: OnboardingFeature

    var body: some View {
        ZStack(alignment: .topLeading) {
            page
                .id(feature)
                .transition(.blurReplace)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.45), value: feature)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Text(feature.title)
                .font(.largeTitle)
                .fontWeight(.black)
                .accessibilityAddTraits(.isHeader)
            Text(feature.description)
                .opacity(0.85)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

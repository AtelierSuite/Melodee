import SwiftUI

struct OnboardingView: View {

    @State private var feature: OnboardingFeature = .music
    var onFinish: () -> Void

    private var isLast: Bool { feature == OnboardingFeature.allCases.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0.0) {
                GlassEffectContainer(spacing: 4.0) {
                    VStack(spacing: 12.0) {
                        OnboardingTrail(current: feature)
                        OnboardingStage(feature: feature)
                    }
                }
                OnboardingText(feature: feature)
                    .padding(.top, 28.0)
            }
            .padding(.horizontal, 24.0)
            .padding(.top, 16.0)
            .padding(.bottom, 24.0)
            .frame(maxWidth: 560.0)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom, spacing: 0.0) {
            OnboardingButton(
                title: String(localized: isLast ? "Onboarding.GetStarted" : "Onboarding.Continue"),
                action: advance
            )
            .frame(maxWidth: 560.0)
            .padding(24.0)
        }
        .background { OnboardingBackground(feature: feature) }
        .interactiveDismissDisabled()
        .presentationDragIndicator(.hidden)
    }

    private func advance() {
        let features = OnboardingFeature.allCases
        guard let index = features.firstIndex(of: feature), index + 1 < features.count else {
            return onFinish()
        }
        feature = features[index + 1]
    }
}

extension OnboardingView {
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static func shouldShow(currentVersion: String, lastSeenVersion: String) -> Bool {
        guard let current = majorMinor(currentVersion) else { return false }
        guard let last = majorMinor(lastSeenVersion) else { return true }
        if current.major != last.major { return current.major > last.major }
        return current.minor > last.minor
    }

    static func majorMinor(_ version: String) -> (major: Int, minor: Int)? {
        let components = version.split(separator: ".")
        guard let major = components.first.flatMap({ Int($0) }) else { return nil }
        let minor = components.count > 1 ? (Int(components[1]) ?? 0) : 0
        return (major, minor)
    }
}

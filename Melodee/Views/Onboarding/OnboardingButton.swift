import SwiftUI

struct OnboardingButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .animation(.smooth, value: title)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .buttonSizing(.flexible)
        .keyboardShortcut(.defaultAction)
    }
}

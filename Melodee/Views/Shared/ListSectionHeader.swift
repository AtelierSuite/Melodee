import SwiftUI

struct ListSectionHeader: View {

    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .bold()
            .foregroundStyle(.primary)
            .textCase(.none)
            .lineLimit(1)
            .truncationMode(.middle)
            .allowsTightening(true)
    }
}

/// A section header that expands and collapses its section when tapped.
struct CollapsibleSectionHeader: View {

    var text: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy.speed(2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                ListSectionHeader(text: text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90.0 : 0.0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }
}

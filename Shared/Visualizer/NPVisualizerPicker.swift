import SwiftUI

/// Everything a style needs to draw one frame.
struct NPVisualizerFrame {
    let bands: [Float]
    let time: TimeInterval
    let colors: NPVisualizerStyle.Colors
    let history: NPVisualizerHistory
}

/// One style, drawn for a frame.
struct NPVisualizerCanvas: View {

    let style: NPVisualizerStyle
    let frame: NPVisualizerFrame

    var body: some View {
        // The canvas redraws because the frame it captures changes every time
        Canvas { context, size in
            style.draw(frame.bands, colors: frame.colors, time: frame.time, history: frame.history,
                       in: &context, size: size)
        }
    }
}

/// A carousel of every style, each drawn live, to choose the one to use.
struct NPVisualizerPicker: View {

    let frame: NPVisualizerFrame
    let selection: NPVisualizerStyle
    let onChoose: (NPVisualizerStyle) -> Void

    @State private var centeredStyle: NPVisualizerStyle?

    var body: some View {
        GeometryReader { geometry in
            let previewSide = min(geometry.size.width, geometry.size.height) * 0.58
            VStack(spacing: 0.0) {
                Spacer(minLength: 0.0)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14.0) {
                        ForEach(NPVisualizerStyle.allCases) { style in
                            preview(of: style, side: previewSide)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geometry.size.width - previewSide) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $centeredStyle, anchor: .center)
                .scrollClipDisabled()
                Spacer(minLength: 0.0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
#if os(macOS)
            // A mouse can't swipe the carousel, so arrows either side step through it
            .overlay {
                HStack {
                    stepButton(by: -1, systemImage: "chevron.backward")
                    Spacer(minLength: previewSide)
                    stepButton(by: 1, systemImage: "chevron.forward")
                }
                .frame(maxWidth: previewSide + 160.0)
            }
#endif
        }
        .onAppear {
            centeredStyle = selection
        }
    }

    private func preview(of style: NPVisualizerStyle, side: CGFloat) -> some View {
        let isSelected = style == selection
        return Button {
            onChoose(style)
        } label: {
            NPVisualizerCanvas(style: style, frame: frame)
                .frame(width: side, height: side)
                .background(.black.opacity(0.35))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5.0) {
                        style.icon
                        Text(verbatim: style.localizedName)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3.0)
                    .padding(10.0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12.0))
                .overlay {
                    RoundedRectangle(cornerRadius: 12.0)
                        .strokeBorder(.white.opacity(isSelected ? 0.9 : 0.2), lineWidth: isSelected ? 2.0 : 0.5)
                }
        }
        .buttonStyle(.plain)
        .scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1.0 : 0.82)
                .opacity(phase.isIdentity ? 1.0 : 0.55)
        }
        .accessibilityLabel(Text(verbatim: style.localizedName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(style)
    }

#if os(macOS)
    private func stepButton(by offset: Int, systemImage: String) -> some View {
        let styles = NPVisualizerStyle.allCases
        let currentIndex = centeredStyle.flatMap(styles.firstIndex(of:)) ?? 0
        let newIndex = currentIndex + offset
        return Button {
            guard styles.indices.contains(newIndex) else { return }
            withAnimation(.smooth) {
                centeredStyle = styles[newIndex]
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18.0, weight: .semibold))
                .frame(width: 28.0, height: 28.0)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .foregroundStyle(.white)
        .opacity(styles.indices.contains(newIndex) ? 1.0 : 0.0)
        .disabled(!styles.indices.contains(newIndex))
        .accessibilityHidden(true)
    }
#endif
}

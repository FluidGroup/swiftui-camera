import SwiftUI

/// The mode row under VSCO Capture's shutter: titles in a line, the selected one centered in white
/// and the rest dimmed. Swipe the row or tap a title to choose.
struct ModeSwitcher<Mode: Hashable>: View {
  let modes: [Mode]
  @Binding var selection: Mode
  let title: (Mode) -> String

  private let slotWidth: CGFloat = 84

  var body: some View {
    // The margins must be right in the first layout, or the scroll view starts off center.
    GeometryReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ForEach(modes, id: \.self) { mode in
            Button {
              withAnimation(.snappy) { selection = mode }
            } label: {
              Text(title(mode))
                .font(.footnote.weight(.semibold))
                .kerning(0.6)
                .foregroundStyle(mode == selection ? Color.white : Color.gray)
                .frame(width: slotWidth, height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(mode == selection ? .isSelected : [])
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: centeredMode, anchor: .center)
      .contentMargins(.horizontal, max((proxy.size.width - slotWidth) / 2, 0), for: .scrollContent)
    }
    .frame(height: 32)
  }

  private var centeredMode: Binding<Mode?> {
    Binding(
      get: { selection },
      set: { mode in
        guard let mode, mode != selection else { return }
        selection = mode
      }
    )
  }
}

#Preview("Mode switcher") {
  @Previewable @State var mode = "PHOTO"
  ModeSwitcher(modes: ["PHOTO", "DSCO", "VIDEO", "MULTI"], selection: $mode) { $0 }
    .padding(.vertical)
    .background(.black)
}

import SwiftUI

/// VSCO Capture's hint: one short line in a dark box, with an arrow on the edge that faces what it
/// explains.
struct CoachMark: View {
  let text: String
  var arrowEdge: Edge = .bottom

  private let arrowSize: CGFloat = 6

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .padding(Edge.Set(arrowEdge), arrowSize)
      .background {
        CoachMarkShape(arrowEdge: arrowEdge, arrowSize: arrowSize)
          .fill(.black.opacity(0.85))
      }
  }
}

nonisolated private struct CoachMarkShape: Shape {
  let arrowEdge: Edge
  let arrowSize: CGFloat

  func path(in rect: CGRect) -> Path {
    var box = rect
    let tip: CGPoint
    let base: (CGPoint, CGPoint)
    // The arrow's base reaches 1 pt into the box, so the union leaves no seam between them.
    switch arrowEdge {
    case .top:
      box.origin.y += arrowSize
      box.size.height -= arrowSize
      tip = CGPoint(x: rect.midX, y: rect.minY)
      base = (CGPoint(x: rect.midX - arrowSize, y: box.minY + 1), CGPoint(x: rect.midX + arrowSize, y: box.minY + 1))
    case .bottom:
      box.size.height -= arrowSize
      tip = CGPoint(x: rect.midX, y: rect.maxY)
      base = (CGPoint(x: rect.midX - arrowSize, y: box.maxY - 1), CGPoint(x: rect.midX + arrowSize, y: box.maxY - 1))
    case .leading:
      box.origin.x += arrowSize
      box.size.width -= arrowSize
      tip = CGPoint(x: rect.minX, y: rect.midY)
      base = (CGPoint(x: box.minX + 1, y: rect.midY - arrowSize), CGPoint(x: box.minX + 1, y: rect.midY + arrowSize))
    case .trailing:
      box.size.width -= arrowSize
      tip = CGPoint(x: rect.maxX, y: rect.midY)
      base = (CGPoint(x: box.maxX - 1, y: rect.midY - arrowSize), CGPoint(x: box.maxX - 1, y: rect.midY + arrowSize))
    }
    var arrow = Path()
    arrow.move(to: base.0)
    arrow.addLine(to: tip)
    arrow.addLine(to: base.1)
    arrow.closeSubpath()
    return Path(roundedRect: box, cornerRadius: 4).union(arrow)
  }
}

#Preview("Coach marks") {
  VStack(spacing: 16) {
    CoachMark(text: "Swipe to try looks", arrowEdge: .bottom)
    CoachMark(text: "Slide to adjust the exposure", arrowEdge: .trailing)
    CoachMark(text: "Tap to flip the camera", arrowEdge: .top)
    CoachMark(text: "Press to take a photo", arrowEdge: .leading)
  }
  .padding()
  .background(.gray)
}

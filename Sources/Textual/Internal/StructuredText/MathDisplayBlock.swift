import SwiftUI

extension StructuredText {
  struct MathDisplayBlock<Content: View>: View {
    @Environment(\.mathProperties) private var mathProperties

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      Overflow { state in
        content
          .fixedSize(horizontal: true, vertical: true)
          .frame(minWidth: state.containerWidth, alignment: alignment)
      }
      .environment(\.overflowMode, .scroll)
        .layoutValue(key: BlockAlignmentKey.self, value: mathProperties.textAlignment)
    }

    private var alignment: Alignment {
      switch mathProperties.textAlignment {
      case .leading:
        .leading
      case .center:
        .center
      case .trailing:
        .trailing
      }
    }
  }
}

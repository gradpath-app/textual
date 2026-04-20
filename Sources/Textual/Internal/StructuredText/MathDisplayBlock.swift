import SwiftUI

extension StructuredText {
  struct MathDisplayBlock<Content: View>: View {
    @Environment(\.mathProperties) private var mathProperties

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      content
        .frame(maxWidth: .infinity, alignment: alignment)
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

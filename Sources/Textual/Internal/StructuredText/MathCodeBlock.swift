import SwiftUI

extension StructuredText {
  struct MathCodeBlock: View {
    @Environment(\.paragraphStyle) private var paragraphStyle

    private let latex: String
    private let indentationLevel: Int

    init(_ content: AttributedSubstring) {
      self.latex = String(content.characters[...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      self.indentationLevel = content.presentationIntent?.indentationLevel ?? 0
    }

    var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = paragraphStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
    }

    private var label: some View {
      MathDisplayBlock {
        MathAttachment(latex: latex, style: .block).body
      }
    }
  }
}

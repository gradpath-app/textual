import SwiftUI

extension StructuredText {
  struct MathBlock: View {
    @Environment(\.paragraphStyle) private var paragraphStyle

    private let content: AttributedSubstring

    init(_ content: AttributedSubstring) {
      self.content = content
    }

    var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = paragraphStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
    }

    @ViewBuilder
    private var label: some View {
      if let attachment = content.attachments().first?.base as? MathAttachment {
        MathDisplayBlock {
          attachment.body
        }
      } else {
        WithInlineStyle(AttributedString(content)) {
          TextFragment($0)
        }
      }
    }

    private var indentationLevel: Int {
      content.presentationIntent?.indentationLevel ?? 0
    }
  }
}

import Foundation
import Testing

@testable import Textual

extension AttributedStringMarkdownParser {
  struct PatternProcessorTests {
    private enum Fixtures {
      static let dogeEmoji = Emoji(
        shortcode: "doge",
        url: URL(string: "https://example.com/doge.png")!
      )
      static let sadDogEmoji = Emoji(
        shortcode: "sad_dog",
        url: URL(string: "https://example.com/sad_dog.png")!
      )
      static let emoji: Set<Emoji> = [dogeEmoji, sadDogEmoji]
    }

    @Test func expandsEmojiInText() throws {
      // given
      let processor = PatternProcessor(syntaxExtensions: [.emoji(Fixtures.emoji)])
      let input = try AttributedString(markdown: "Hello :doge: and :sad_dog:")

      var expected = try AttributedString(markdown: "Hello doge and sad_dog")

      let doge = try #require(expected.range(of: "doge"))
      let sadDog = try #require(expected.range(of: "sad_dog"))

      expected[doge].textual.emojiURL = Fixtures.dogeEmoji.url
      expected[sadDog].textual.emojiURL = Fixtures.sadDogEmoji.url

      // when
      let output = try processor.expand(input)

      // then
      #expect(output == expected)
    }

    @Test func ignoresEmojiInInlineCode() throws {
      // given
      let processor = PatternProcessor(syntaxExtensions: [.emoji(Fixtures.emoji)])
      let input = try AttributedString(markdown: "Hello `:doge:` and :doge:")

      var expected = try AttributedString(markdown: "Hello `:doge:` and doge")

      let doge = try #require(expected.range(of: "doge", options: .backwards))
      expected[doge].textual.emojiURL = Fixtures.dogeEmoji.url

      // when
      let output = try processor.expand(input)

      // then
      #expect(output == expected)
    }

    @Test func ignoresEmojiInCodeBlock() throws {
      // given
      let processor = PatternProcessor(syntaxExtensions: [.emoji(Fixtures.emoji)])
      let input = try AttributedString(
        markdown: """
          ```
          :doge:
          ```
          :doge:
          """
      )

      var expected = try AttributedString(
        markdown: """
          ```
          :doge:
          ```
          doge
          """
      )

      let doge = try #require(expected.range(of: "doge", options: .backwards))
      expected[doge].textual.emojiURL = Fixtures.dogeEmoji.url

      // when
      let output = try processor.expand(input)

      // then
      #expect(output == expected)
    }

    @Test func ignoresEmojiInNestedCodeBlock() throws {
      // given
      let processor = PatternProcessor(syntaxExtensions: [.emoji(Fixtures.emoji)])
      let input = try AttributedString(
        markdown: """
          > ```
          > :doge:
          > ```
          > :doge:
          """
      )

      var expected = try AttributedString(
        markdown: """
          > ```
          > :doge:
          > ```
          > doge
          """
      )

      let doge = try #require(expected.range(of: "doge", options: .backwards))
      expected[doge].textual.emojiURL = Fixtures.dogeEmoji.url

      // when
      let output = try processor.expand(input)

      // then
      #expect(output == expected)
    }

    @MainActor
    @Test func parserPreservesMultilineInlineMathAsSingleAttachment() throws {
      // given
      let parser = AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math])
      let input = """
        设直线 $\\begin{cases}
        x=0,\\\\
        y=0
        \\end{cases}$ 绕轴旋转
        """

      // when
      let attributed = try parser.attributedString(for: input)
      let attachments = attributed.attachments()

      // then
      #expect(attachments.count == 1)
      #expect(attachments.first?.description == "$\\begin{cases}\nx=0,\\\\\ny=0\n\\end{cases}$")
    }
  }
}

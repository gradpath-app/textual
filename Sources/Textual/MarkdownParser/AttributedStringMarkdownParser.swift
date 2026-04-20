import Foundation

/// A ``MarkupParser`` implementation backed by Foundation's Markdown support.
///
/// This parser leverages Foundation's Markdown support and preserves structure via
/// presentation intents.
///
/// This parser can process its output to expand custom emoji and math expressions into
/// inline attachments.
public struct AttributedStringMarkdownParser: MarkupParser {
  private let baseURL: URL?
  private let options: AttributedString.MarkdownParsingOptions
  private let processor: PatternProcessor
  // Whether the .math syntax extension is active. When true, we pre-extract LaTeX from the
  // source string before Markdown parsing so that Foundation's parser cannot corrupt
  // subscripts (`_`), emphasis (`*`), or array line-breaks (`\\`) that appear inside formulas.
  private let hasMath: Bool

  public init(
    baseURL: URL?,
    options: AttributedString.MarkdownParsingOptions = .init(),
    syntaxExtensions: [SyntaxExtension] = []
  ) {
    self.baseURL = baseURL
    self.options = options
    self.processor = PatternProcessor(syntaxExtensions: syntaxExtensions)
    self.hasMath = syntaxExtensions.contains { ext in
      ext.patterns.contains { $0.tokenType == .mathBlock || $0.tokenType == .mathInline }
    }
  }

  public func attributedString(for input: String) throws -> AttributedString {
    // When math is active, protect LaTeX content before Markdown parsing.
    // Foundation's parser runs first and would corrupt `_` (subscripts → italic),
    // `\\` (array line-breaks → escaped backslash), and `*` inside formulas.
    if hasMath, input.contains("$") {
      var mathStore: [(latex: String, isBlock: Bool)] = []
      let protectedInput = Self.extractMath(from: input, into: &mathStore)

      var attributed = try AttributedString(
        markdown: protectedInput,
        including: \.textual,
        options: options,
        baseURL: baseURL
      )

      if !mathStore.isEmpty {
        attributed = Self.restoreMath(in: attributed, from: mathStore)
      }

      // processor.expand handles remaining extensions (emoji, etc.);
      // math placeholders have already been restored above.
      return try processor.expand(attributed)
    } else {
      return try processor.expand(
        AttributedString(
          markdown: input,
          including: \.textual,
          options: options,
          baseURL: baseURL
        )
      )
    }
  }
}

extension MarkupParser where Self == AttributedStringMarkdownParser {
  /// Creates a Markdown parser configured for inline-only syntax.
  public static func inlineMarkdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
      syntaxExtensions: syntaxExtensions
    )
  }

  /// Creates a Markdown parser configured for full-document syntax.
  public static func markdown(
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) -> Self {
    .init(
      baseURL: baseURL,
      syntaxExtensions: syntaxExtensions
    )
  }
}

// MARK: - Math pre-extraction

extension AttributedStringMarkdownParser {

  // Replaces $$...$$ and $...$ in `source` with safe alphanumeric placeholders that Foundation's
  // Markdown parser will not modify. The extracted LaTeX strings (with their block/inline flag)
  // are appended to `store` in the order they appear in the source.
  //
  // Placeholder format:
  //   block math  → GRADPATHBLOCK<N>
  //   inline math → GRADPATHINLINE<N>
  // where N is the zero-based index into `store`.
  static func extractMath(
    from source: String,
    into store: inout [(latex: String, isBlock: Bool)]
  ) -> String {
    // Combined ICU pattern: block ($$...$$) is listed first so $$ is never consumed by the
    // inline branch. (?s) makes `.` match newlines so we can preserve multi-line inline math
    // content such as `$\\begin{cases} ... \\end{cases}$`, which is valid in LaTeX-style math.
    let pattern = #"(?s)\$\$(.+?)\$\$|\$(?!\$)((?:\\\$|[^\$])+)\$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }

    var result = ""
    var lastIndex = source.startIndex
    let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))

    for match in matches {
      guard let fullRange = Range(match.range, in: source) else { continue }

      // Append text before this match unchanged
      result += source[lastIndex..<fullRange.lowerBound]

      let index = store.count
      let blockCapture = match.range(at: 1)
      let inlineCapture = match.range(at: 2)

      if blockCapture.location != NSNotFound, let r = Range(blockCapture, in: source) {
        store.append((latex: String(source[r]), isBlock: true))
        result += "GRADPATHBLOCK\(index)"
      } else if inlineCapture.location != NSNotFound, let r = Range(inlineCapture, in: source) {
        store.append((latex: String(source[r]), isBlock: false))
        result += "GRADPATHINLINE\(index)"
      }

      lastIndex = fullRange.upperBound
    }

    result += source[lastIndex...]
    return result
  }

  // Replaces GRADPATHBLOCK<N> / GRADPATHINLINE<N> placeholders in `attributed` with
  // MathAttachment nodes, preserving all other run attributes (presentation intent, etc.).
  static func restoreMath(
    in attributed: AttributedString,
    from store: [(latex: String, isBlock: Bool)]
  ) -> AttributedString {
    guard
      let regex = try? NSRegularExpression(
        pattern: #"GRADPATHBLOCK(\d+)|GRADPATHINLINE(\d+)"#)
    else { return attributed }

    var output = AttributedString()

    for run in attributed.runs {
      let runSlice = attributed[run.range]
      let text = String(runSlice.characters[...])
      let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

      if matches.isEmpty {
        output.append(runSlice)
        continue
      }

      var lastIndex = text.startIndex

      for match in matches {
        guard let matchRange = Range(match.range, in: text) else { continue }

        // Append any text before this placeholder
        if lastIndex < matchRange.lowerBound {
          let prefix = String(text[lastIndex..<matchRange.lowerBound])
          output.append(AttributedString(prefix, attributes: run.attributes))
        }

        // Resolve which store entry this placeholder refers to
        let blockIndex = match.range(at: 1)
        let inlineIndex = match.range(at: 2)
        let storeIndex: Int?

        if blockIndex.location != NSNotFound,
          let r = Range(blockIndex, in: text),
          let n = Int(text[r])
        {
          storeIndex = n
        } else if inlineIndex.location != NSNotFound,
          let r = Range(inlineIndex, in: text),
          let n = Int(text[r])
        {
          storeIndex = n
        } else {
          storeIndex = nil
        }

        if let idx = storeIndex, idx < store.count {
          let (latex, isBlock) = store[idx]
          let mathAttachment = MathAttachment(latex: latex, style: isBlock ? .block : .inline)
          // Mirror the pattern used by SyntaxExtension.math: preserve the run's attributes
          // (presentation intent, links, etc.) and overlay the attachment.
          output.append(
            AttributedString(
              "\u{FFFC}",
              attributes: run.attributes.attachment(.init(mathAttachment))
            )
          )
        }

        lastIndex = matchRange.upperBound
      }

      // Append any text after the last placeholder
      if lastIndex < text.endIndex {
        let suffix = String(text[lastIndex...])
        output.append(AttributedString(suffix, attributes: run.attributes))
      }
    }

    return output
  }
}

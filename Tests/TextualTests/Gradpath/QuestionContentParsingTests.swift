import Foundation
import SwiftUI
import Testing
@_spi(Textual) import SwiftUIMath

@testable import Textual

@MainActor
struct QuestionContentParsingTests {
  // These integration tests read the sibling GradPath CMS checkout. When the
  // content repo is unavailable in the current workspace, treat the tests as no-ops.
  private struct QuestionRecord: Sendable {
    let sourceId: String
    let stem: String
    let options: [String]
    let answer: String
    let analysis: String
    let imageAssetSourceIds: [String]
  }

  private struct ImageAssetRecord: Sendable {
    let sourceId: String
    let filename: String
  }

  private struct FormulaIssue: Sendable {
    let sourceId: String
    let field: String
    let description: String
  }

  private struct ImageIssue: Sendable {
    let sourceId: String
    let field: String
    let kind: String
    let reference: String
    let relatedImageAssetSourceIds: [String]
  }

  private struct TableIssue: Sendable {
    let sourceId: String
    let field: String
    let kind: String
    let description: String
  }

  private struct ParsedTableBlock: Sendable {
    let columnCount: Int
    let identity: Int
  }

  private struct MarkdownTableBlock: Sendable {
    let headerLine: String
    let lineNumber: Int
  }

  private struct Report: Sendable {
    let questionCount: Int
    let formulaAttachmentCount: Int
    let formulaIssues: [FormulaIssue]
    let imageQuestionCount: Int
    let imageReferenceCount: Int
    let imageIssues: [ImageIssue]
    let parsedTableCount: Int
    let tableIssues: [TableIssue]
    let tableQuestionCount: Int
    let tableReferenceCount: Int

    var summary: String {
      let formulaLines = formulaIssues.prefix(10).map {
        "  - \($0.sourceId) [\($0.field)] \($0.description)"
      }
      let imageLines = imageIssues.prefix(10).map {
        let related = $0.relatedImageAssetSourceIds.isEmpty ? "-" : $0.relatedImageAssetSourceIds.joined(separator: ",")
        return "  - \($0.sourceId) [\($0.field)] \($0.kind): \($0.reference) (related=\(related))"
      }
      let tableLines = tableIssues.prefix(10).map {
        "  - \($0.sourceId) [\($0.field)] \($0.kind): \($0.description)"
      }

      return """
        Gradpath CMS rich-text report
        questions=\(questionCount)
        formulaAttachments=\(formulaAttachmentCount)
        formulaIssues=\(formulaIssues.count)
        \(formulaLines.joined(separator: "\n"))
        imageQuestions=\(imageQuestionCount)
        imageReferences=\(imageReferenceCount)
        imageIssues=\(imageIssues.count)
        \(imageLines.joined(separator: "\n"))
        tableQuestions=\(tableQuestionCount)
        parsedTables=\(parsedTableCount)
        tableReferences=\(tableReferenceCount)
        tableIssues=\(tableIssues.count)
        \(tableLines.joined(separator: "\n"))
        """
    }
  }

  private enum Paths {
    static let packageRoot: URL = {
      var url = URL(fileURLWithPath: #filePath)
      for _ in 0..<4 {
        url.deleteLastPathComponent()
      }
      return url
    }()

    static let contentRoot = URL(
      fileURLWithPath: "/Volumes/APFS/codes/gradpath/gradpath-studio/content",
      isDirectory: true
    )
    static let questionsRoot = contentRoot.appendingPathComponent("questions", isDirectory: true)
    static let imageAssetsRoot = contentRoot.appendingPathComponent("image-assets", isDirectory: true)
    static let reportsRoot = packageRoot.appendingPathComponent(".build/reports", isDirectory: true)
    static let htmlReport = reportsRoot.appendingPathComponent("gradpath-question-rich-text-report.html")
  }

  private static var hasRequiredCMSFixtures: Bool {
    let fileManager = FileManager.default

    guard
      fileManager.fileExists(atPath: Paths.questionsRoot.path),
      fileManager.fileExists(atPath: Paths.imageAssetsRoot.path)
    else {
      return false
    }

    let representativeQuestionIDs = [
      "51a1f663-80b7-440b-aaa8-2ff84a3f16c7",
      "506eaa73-47f9-4a54-a86a-5251fcd01ba1",
      "1c84e8ef-c0c6-4303-81b0-6821d5c9b518",
    ]

    return representativeQuestionIDs.allSatisfy { sourceId in
      fileManager.fileExists(
        atPath: Paths.questionsRoot.appendingPathComponent("\(sourceId).toml").path
      )
    }
  }

  @Test func parsesRepresentativeQuestionAnalysisWithMathAndLocalImages() throws {
    guard Self.hasRequiredCMSFixtures else { return }
    let question = try Self.loadQuestion(sourceId: "51a1f663-80b7-440b-aaa8-2ff84a3f16c7")
    let attributed = try Self.makeContentParser().attributedString(for: question.analysis)

    #expect(Self.mathAttachments(in: attributed).count >= 4)
    #expect(Self.imageURLs(in: attributed).count == 4)
  }

  @Test func parsesRepresentativeQuestionStemWithMathAndLocalImage() throws {
    guard Self.hasRequiredCMSFixtures else { return }
    let question = try Self.loadQuestion(sourceId: "506eaa73-47f9-4a54-a86a-5251fcd01ba1")
    let attributed = try Self.makeContentParser().attributedString(for: question.stem)
    let urls = Self.imageURLs(in: attributed)

    #expect(Self.mathAttachments(in: attributed).count >= 3)
    #expect(urls.count == 1)
    #expect(urls.first?.lastPathComponent == "q506eaa73_img0_6c285c58.png")
  }

  @Test func parsesRepresentativeQuestionStemWithMarkdownTables() throws {
    guard Self.hasRequiredCMSFixtures else { return }
    let question = try Self.loadQuestion(sourceId: "1c84e8ef-c0c6-4303-81b0-6821d5c9b518")
    let attributed = try Self.makeContentParser().attributedString(for: question.stem)
    let rawTables = Self.markdownTables(in: question.stem)
    let parsedTables = Self.parsedTables(in: attributed)

    #expect(rawTables.count == 1)
    #expect(parsedTables.count == 1)
    #expect(parsedTables.first?.columnCount == 3)
  }

  @Test func scansCurrentCMSQuestionsAndPrintsRichTextIssueReport() throws {
    guard Self.hasRequiredCMSFixtures else { return }
    let report = try Self.buildReport()
    let reportURL = try Self.writeHTMLReport(report)
    print(report.summary)
    print("HTML report written to: \(reportURL.path)")

    #expect(report.questionCount > 2000)
    #expect(report.formulaAttachmentCount > 30000)
    #expect(report.imageQuestionCount > 50)
    #expect(report.imageReferenceCount > 70)
    #expect(report.tableQuestionCount > 40)
    #expect(report.tableReferenceCount > 80)
    #expect(FileManager.default.fileExists(atPath: reportURL.path))
  }

  private static func buildReport() throws -> Report {
    let questions = try loadQuestions()
    let imageAssets = try loadImageAssets()
    let parser = makeContentParser()

    let filenamesBySourceId = Dictionary(uniqueKeysWithValues: imageAssets.map { ($0.sourceId, $0.filename) })
    let sourceIdsByFilename = Dictionary(grouping: imageAssets, by: \.filename)
      .mapValues { $0.map(\.sourceId).sorted() }

    var formulaAttachmentCount = 0
    var formulaIssues: [FormulaIssue] = []
    var imageQuestionCount = 0
    var imageReferenceCount = 0
    var imageIssues: [ImageIssue] = []
    var parsedTableCount = 0
    var tableQuestionCount = 0
    var tableReferenceCount = 0
    var tableIssues: [TableIssue] = []

    for question in questions {
      let linkedFilenames = Set(question.imageAssetSourceIds.compactMap { filenamesBySourceId[$0] })
      var questionHasImageReference = false
      var questionHasTableReference = false

      for (field, value) in richTextFields(for: question) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          continue
        }

        let attributed: AttributedString
        do {
          attributed = try parser.attributedString(for: value)
        } catch {
          formulaIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              description: "markdown parse failed: \(error.localizedDescription)"
            )
          )
          continue
        }

        let attachments = mathAttachments(in: attributed)
        formulaAttachmentCount += attachments.count

        if containsPotentialMathMarkup(in: value), attachments.isEmpty {
          formulaIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              description: "math markers found but Textual produced no math attachments"
            )
          )
        }

        let delimiters = unmatchedMathDelimiters(in: value)
        if delimiters.hasUnmatchedSingle {
          formulaIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              description: "unmatched single-dollar delimiter"
            )
          )
        }
        if delimiters.hasUnmatchedDouble {
          formulaIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              description: "unmatched double-dollar delimiter"
            )
          )
        }

        for attachment in attachments {
          if !isRenderableMathAttachment(attachment) {
            formulaIssues.append(
              .init(
                sourceId: question.sourceId,
                field: field,
                description: "math attachment failed layout: \(attachment.description)"
              )
            )
          }
        }

        let rawImageReferences = Self.imageReferences(in: value)
        if !rawImageReferences.isEmpty {
          questionHasImageReference = true
        }
        imageReferenceCount += rawImageReferences.count

        let parsedImageURLs = imageURLs(in: attributed)
        if parsedImageURLs.count != rawImageReferences.count {
          imageIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              kind: "parser-mismatch",
              reference: "raw=\(rawImageReferences.count), parsed=\(parsedImageURLs.count)",
              relatedImageAssetSourceIds: []
            )
          )
        }

        for reference in rawImageReferences {
          if isRemoteImageReference(reference) {
            imageIssues.append(
              .init(
                sourceId: question.sourceId,
                field: field,
                kind: "remote-image-url",
                reference: reference,
                relatedImageAssetSourceIds: []
              )
            )
            continue
          }

          let filename = URL(fileURLWithPath: reference).lastPathComponent
          let relatedImageAssetSourceIds = sourceIdsByFilename[filename] ?? []

          if relatedImageAssetSourceIds.isEmpty {
            imageIssues.append(
              .init(
                sourceId: question.sourceId,
                field: field,
                kind: "missing-asset",
                reference: reference,
                relatedImageAssetSourceIds: []
              )
            )
            continue
          }

          if !linkedFilenames.contains(filename) {
            imageIssues.append(
              .init(
                sourceId: question.sourceId,
                field: field,
                kind: "unlinked-asset",
                reference: reference,
                relatedImageAssetSourceIds: relatedImageAssetSourceIds
              )
            )
          }
        }

        let rawTables = markdownTables(in: value)
        let parsedTables = parsedTables(in: attributed)
        if !rawTables.isEmpty {
          questionHasTableReference = true
        }
        tableReferenceCount += rawTables.count
        parsedTableCount += parsedTables.count

        if rawTables.count != parsedTables.count {
          tableIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              kind: "parser-mismatch",
              description: "raw=\(rawTables.count), parsed=\(parsedTables.count)"
            )
          )
        }

        for table in parsedTables where table.columnCount == 0 {
          tableIssues.append(
            .init(
              sourceId: question.sourceId,
              field: field,
              kind: "invalid-columns",
              description: "parsed table identity \(table.identity) has 0 columns"
            )
          )
        }
      }

      if questionHasImageReference {
        imageQuestionCount += 1
      }
      if questionHasTableReference {
        tableQuestionCount += 1
      }
    }

    return .init(
      questionCount: questions.count,
      formulaAttachmentCount: formulaAttachmentCount,
      formulaIssues: deduplicatedFormulaIssues(formulaIssues),
      imageQuestionCount: imageQuestionCount,
      imageReferenceCount: imageReferenceCount,
      imageIssues: deduplicatedImageIssues(imageIssues),
      parsedTableCount: parsedTableCount,
      tableIssues: deduplicatedTableIssues(tableIssues),
      tableQuestionCount: tableQuestionCount,
      tableReferenceCount: tableReferenceCount
    )
  }

  private static func loadQuestion(sourceId: String) throws -> QuestionRecord {
    let url = Paths.questionsRoot.appendingPathComponent("\(sourceId).toml")
    return try parseQuestion(at: url)
  }

  private static func loadQuestions() throws -> [QuestionRecord] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: Paths.questionsRoot,
      includingPropertiesForKeys: nil
    )
      .filter { $0.pathExtension == "toml" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try urls.map(parseQuestion(at:))
  }

  private static func loadImageAssets() throws -> [ImageAssetRecord] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: Paths.imageAssetsRoot,
      includingPropertiesForKeys: nil
    )
      .filter { $0.pathExtension == "toml" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try urls.map(parseImageAsset(at:))
  }

  private static func makeContentParser() -> AttributedStringMarkdownParser {
    AttributedStringMarkdownParser(
      baseURL: Paths.contentRoot,
      syntaxExtensions: [.math]
    )
  }

  private static func writeHTMLReport(_ report: Report) throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: Paths.reportsRoot, withIntermediateDirectories: true)
    let html = makeHTMLReport(report)
    try html.write(to: Paths.htmlReport, atomically: true, encoding: .utf8)
    return Paths.htmlReport
  }

  private static func makeHTMLReport(_ report: Report) -> String {
    let formatter = ISO8601DateFormatter()
    let generatedAt = formatter.string(from: Date())

    let formulaRows = report.formulaIssues.enumerated().map { index, issue in
      """
      <tr>
        <td class="num">\(index + 1)</td>
        <td><code>\(escapeHTML(issue.sourceId))</code></td>
        <td><code>\(escapeHTML(issue.field))</code></td>
        <td>\(escapeHTML(issue.description))</td>
      </tr>
      """
    }.joined(separator: "\n")

    let imageRows = report.imageIssues.enumerated().map { index, issue in
      let related = issue.relatedImageAssetSourceIds.isEmpty
        ? "-"
        : issue.relatedImageAssetSourceIds.joined(separator: ", ")

      return """
      <tr>
        <td class="num">\(index + 1)</td>
        <td><code>\(escapeHTML(issue.sourceId))</code></td>
        <td><code>\(escapeHTML(issue.field))</code></td>
        <td><code>\(escapeHTML(issue.kind))</code></td>
        <td>\(escapeHTML(issue.reference))</td>
        <td><code>\(escapeHTML(related))</code></td>
      </tr>
      """
    }.joined(separator: "\n")

    let formulaSection = report.formulaIssues.isEmpty
      ? "<p class=\"empty\">No formula issues found.</p>"
      : """
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Question</th>
            <th>Field</th>
            <th>Description</th>
          </tr>
        </thead>
        <tbody>
          \(formulaRows)
        </tbody>
      </table>
      """

    let imageSection = report.imageIssues.isEmpty
      ? "<p class=\"empty\">No image issues found.</p>"
      : """
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Question</th>
            <th>Field</th>
            <th>Kind</th>
            <th>Reference</th>
            <th>Related Assets</th>
          </tr>
        </thead>
        <tbody>
          \(imageRows)
        </tbody>
      </table>
      """

    let tableRows = report.tableIssues.enumerated().map { index, issue in
      """
      <tr>
        <td class="num">\(index + 1)</td>
        <td><code>\(escapeHTML(issue.sourceId))</code></td>
        <td><code>\(escapeHTML(issue.field))</code></td>
        <td><code>\(escapeHTML(issue.kind))</code></td>
        <td>\(escapeHTML(issue.description))</td>
      </tr>
      """
    }.joined(separator: "\n")

    let tableSection = report.tableIssues.isEmpty
      ? "<p class=\"empty\">No table issues found.</p>"
      : """
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Question</th>
            <th>Field</th>
            <th>Kind</th>
            <th>Description</th>
          </tr>
        </thead>
        <tbody>
          \(tableRows)
        </tbody>
      </table>
      """

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Gradpath Question Rich Text Report</title>
      <style>
        :root {
          color-scheme: light;
          --bg: #f6f4ef;
          --panel: #fffdf8;
          --line: #ddd6c8;
          --text: #1d1b18;
          --muted: #6e675f;
          --accent: #9c4f2f;
          --accent-soft: #f7e6de;
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          font-family: "Iowan Old Style", "Palatino Linotype", serif;
          background: linear-gradient(180deg, #efe7db 0%, var(--bg) 100%);
          color: var(--text);
        }
        main {
          max-width: 1200px;
          margin: 0 auto;
          padding: 32px 24px 64px;
        }
        h1, h2 {
          margin: 0;
          font-weight: 700;
        }
        h1 {
          font-size: 34px;
          letter-spacing: -0.02em;
        }
        h2 {
          font-size: 24px;
          margin-top: 36px;
          margin-bottom: 16px;
        }
        p {
          line-height: 1.6;
        }
        .meta {
          margin-top: 10px;
          color: var(--muted);
        }
        .cards {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
          gap: 14px;
          margin-top: 28px;
        }
        .card {
          background: var(--panel);
          border: 1px solid var(--line);
          border-radius: 16px;
          padding: 18px 16px;
          box-shadow: 0 10px 30px rgba(60, 43, 20, 0.06);
        }
        .label {
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted);
        }
        .value {
          margin-top: 8px;
          font-size: 30px;
          color: var(--accent);
        }
        table {
          width: 100%;
          border-collapse: collapse;
          background: var(--panel);
          border: 1px solid var(--line);
          border-radius: 16px;
          overflow: hidden;
          box-shadow: 0 10px 30px rgba(60, 43, 20, 0.06);
        }
        th, td {
          padding: 12px 14px;
          text-align: left;
          vertical-align: top;
          border-bottom: 1px solid var(--line);
        }
        th {
          background: var(--accent-soft);
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }
        tr:last-child td {
          border-bottom: none;
        }
        td.num {
          width: 56px;
          color: var(--muted);
        }
        code {
          font-family: "SF Mono", "Menlo", monospace;
          font-size: 12px;
          word-break: break-all;
        }
        .empty {
          padding: 18px 20px;
          border: 1px solid var(--line);
          border-radius: 16px;
          background: var(--panel);
        }
      </style>
    </head>
    <body>
      <main>
        <h1>Gradpath Question Rich Text Report</h1>
        <p class="meta">Generated at \(escapeHTML(generatedAt)) by Textual Swift tests.</p>

        <section class="cards">
          <article class="card">
            <div class="label">Questions</div>
            <div class="value">\(report.questionCount)</div>
          </article>
          <article class="card">
            <div class="label">Formula Attachments</div>
            <div class="value">\(report.formulaAttachmentCount)</div>
          </article>
          <article class="card">
            <div class="label">Formula Issues</div>
            <div class="value">\(report.formulaIssues.count)</div>
          </article>
          <article class="card">
            <div class="label">Image Questions</div>
            <div class="value">\(report.imageQuestionCount)</div>
          </article>
          <article class="card">
            <div class="label">Image References</div>
            <div class="value">\(report.imageReferenceCount)</div>
          </article>
          <article class="card">
            <div class="label">Image Issues</div>
            <div class="value">\(report.imageIssues.count)</div>
          </article>
          <article class="card">
            <div class="label">Table Questions</div>
            <div class="value">\(report.tableQuestionCount)</div>
          </article>
          <article class="card">
            <div class="label">Table References</div>
            <div class="value">\(report.tableReferenceCount)</div>
          </article>
          <article class="card">
            <div class="label">Parsed Tables</div>
            <div class="value">\(report.parsedTableCount)</div>
          </article>
          <article class="card">
            <div class="label">Table Issues</div>
            <div class="value">\(report.tableIssues.count)</div>
          </article>
        </section>

        <section>
          <h2>Formula Issues</h2>
          \(formulaSection)
        </section>

        <section>
          <h2>Image Issues</h2>
          \(imageSection)
        </section>

        <section>
          <h2>Table Issues</h2>
          \(tableSection)
        </section>
      </main>
    </body>
    </html>
    """
  }

  private static func parseQuestion(at url: URL) throws -> QuestionRecord {
    let source = try String(contentsOf: url, encoding: .utf8)
    let fields = try parseFields(
      source,
      interestedKeys: ["sourceId", "__sourceId", "stem", "options", "answer", "analysis", "imageAssetSourceIds"]
    )

    return .init(
      sourceId: try requiredString(from: fields, keys: ["sourceId", "__sourceId"]),
      stem: try requiredString(from: fields, key: "stem"),
      options: stringArray(from: fields, key: "options") ?? [],
      answer: try requiredString(from: fields, key: "answer"),
      analysis: try requiredString(from: fields, key: "analysis"),
      imageAssetSourceIds: stringArray(from: fields, key: "imageAssetSourceIds") ?? []
    )
  }

  private static func parseImageAsset(at url: URL) throws -> ImageAssetRecord {
    let source = try String(contentsOf: url, encoding: .utf8)
    let fields = try parseFields(source, interestedKeys: ["sourceId", "__sourceId", "filename"])

    return .init(
      sourceId: try requiredString(from: fields, keys: ["sourceId", "__sourceId"]),
      filename: try requiredString(from: fields, key: "filename")
    )
  }

  private static func parseFields(
    _ source: String,
    interestedKeys: Set<String>
  ) throws -> [String: ParsedFieldValue] {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var index = 0
    var fields: [String: ParsedFieldValue] = [:]

    while index < lines.count {
      let line = lines[index]
      guard let equalsIndex = line.firstIndex(of: "=") else {
        index += 1
        continue
      }

      let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
      guard interestedKeys.contains(key) else {
        index += 1
        continue
      }

      let rhs = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
      if rhs.hasPrefix("[") {
        fields[key] = .array(try parseArray(initialValue: rhs, lines: lines, index: &index))
      } else {
        fields[key] = .string(try parseString(initialValue: rhs, lines: lines, index: &index))
      }

      index += 1
    }

    return fields
  }

  private static func parseArray(
    initialValue: String,
    lines: [String],
    index: inout Int
  ) throws -> [String] {
    let trimmed = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "[]" {
      return []
    }
    guard trimmed == "[" else {
      throw ParseError("unsupported array literal: \(trimmed)")
    }

    var items: [String] = []
    index += 1
    while index < lines.count {
      let rawLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
      if rawLine == "]" {
        index -= 1
        return items
      }
      if rawLine.isEmpty {
        index += 1
        continue
      }

      let itemToken: String
      if rawLine == "'''" || rawLine == "\"\"\"" {
        itemToken = rawLine
      } else if rawLine.hasPrefix("'''") || rawLine.hasPrefix("\"\"\"") {
        itemToken = rawLine.hasSuffix(",") ? String(rawLine.dropLast()) : rawLine
      } else {
        itemToken = rawLine.hasSuffix(",") ? String(rawLine.dropLast()) : rawLine
      }

      items.append(try parseString(initialValue: itemToken, lines: lines, index: &index))
      index += 1
    }

    throw ParseError("unterminated array literal")
  }

  private static func parseString(
    initialValue: String,
    lines: [String],
    index: inout Int
  ) throws -> String {
    let trimmed = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed == "'''" || trimmed == "\"\"\"" {
      let terminator = trimmed
      index += 1
      var bodyLines: [String] = []
      while index < lines.count {
        let trimmedLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine == terminator || trimmedLine == "\(terminator)," {
          return bodyLines.joined(separator: "\n")
        }
        bodyLines.append(lines[index])
        index += 1
      }
      throw ParseError("unterminated multiline string")
    }

    if trimmed.hasPrefix("'''"), trimmed.hasSuffix("'''"), trimmed.count >= 6 {
      return String(trimmed.dropFirst(3).dropLast(3))
    }

    if trimmed.hasPrefix("\"\"\""), trimmed.hasSuffix("\"\"\""), trimmed.count >= 6 {
      let body = String(trimmed.dropFirst(3).dropLast(3))
      return try decodeBasicString("\"\(body)\"")
    }

    return try parseInlineStringToken(trimmed)
  }

  private static func parseInlineStringToken(_ token: String) throws -> String {
    if token.hasPrefix("'"), token.hasSuffix("'"), token.count >= 2 {
      return String(token.dropFirst().dropLast())
    }

    if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
      return try decodeBasicString(token)
    }

    throw ParseError("unsupported string token: \(token)")
  }

  private static func decodeBasicString(_ token: String) throws -> String {
    let data = Data(token.utf8)
    return try JSONDecoder().decode(String.self, from: data)
  }

  private static func richTextFields(for question: QuestionRecord) -> [(String, String)] {
    var fields: [(String, String)] = [
      ("stem", question.stem),
      ("answer", question.answer),
      ("analysis", question.analysis),
    ]

    for (index, option) in question.options.enumerated() {
      fields.append(("options[\(index)]", option))
    }

    return fields
  }

  private static func mathAttachments(in attributed: AttributedString) -> [AnyAttachment] {
    attributed.runs.compactMap { $0.attributes.textual.attachment }.filter {
      let description = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return description.hasPrefix("$") && description.hasSuffix("$")
    }
  }

  private static func imageURLs(in attributed: AttributedString) -> [URL] {
    attributed.runs.compactMap(\.imageURL)
  }

  private static func isRenderableMathAttachment(_ attachment: AnyAttachment) -> Bool {
    let description = attachment.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let latex: String
    let style: Math.TypesettingStyle

    if description.hasPrefix("$$"), description.hasSuffix("$$"), description.count >= 4 {
      latex = String(description.dropFirst(2).dropLast(2))
      style = .display
    } else if description.hasPrefix("$"), description.hasSuffix("$"), description.count >= 2 {
      latex = String(description.dropFirst().dropLast())
      style = .text
    } else {
      return true
    }

    let bounds = Math.typographicBounds(
      for: latex,
      fitting: ProposedViewSize(width: 360, height: nil),
      font: .init(name: .latinModern, size: 20),
      style: style
    )

    return bounds.size != .zero
      && bounds.width.isFinite
      && bounds.ascent.isFinite
      && bounds.descent.isFinite
  }

  private static func imageReferences(in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*]\(([^)]+)\)"#) else {
      return []
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      guard match.numberOfRanges > 1, let capture = Range(match.range(at: 1), in: text) else {
        return nil
      }
      return String(text[capture])
    }
  }

  private static func markdownTables(in text: String) -> [MarkdownTableBlock] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var tables: [MarkdownTableBlock] = []
    var index = 0

    while index + 1 < lines.count {
      let header = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
      let separator = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)

      if header.contains("|"), isMarkdownTableSeparator(separator) {
        tables.append(.init(headerLine: header, lineNumber: index + 1))
        index += 2
        continue
      }

      index += 1
    }

    return tables
  }

  private static func isMarkdownTableSeparator(_ line: String) -> Bool {
    guard line.contains("|") else {
      return false
    }

    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.hasPrefix("|") ? String(trimmed.dropFirst()) : trimmed
    let segments = normalized.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard !segments.isEmpty else {
      return false
    }

    return segments.allSatisfy { segment in
      let core = segment.replacingOccurrences(of: ":", with: "")
      return core.count >= 3 && core.allSatisfy { $0 == "-" }
    }
  }

  private static func parsedTables(in attributed: AttributedString) -> [ParsedTableBlock] {
    var tables: [Int: Int] = [:]

    for run in attributed.runs {
      guard let presentationIntent = run.presentationIntent else {
        continue
      }

      for component in presentationIntent.components {
        if case .table(let columns) = component.kind {
          tables[component.identity] = max(tables[component.identity] ?? 0, columns.count)
        }
      }
    }

    return tables
      .map { .init(columnCount: $0.value, identity: $0.key) }
      .sorted { $0.identity < $1.identity }
  }

  private static func isRemoteImageReference(_ value: String) -> Bool {
    value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
  }

  private static func containsPotentialMathMarkup(in text: String) -> Bool {
    if text.contains("$$") || text.contains("\\(") || text.contains("\\[") {
      return true
    }

    return text.filter { $0 == "$" }.count >= 2
  }

  private static func unmatchedMathDelimiters(in text: String) -> (hasUnmatchedSingle: Bool, hasUnmatchedDouble: Bool) {
    var singleOpen = false
    var doubleOpen = false
    var index = text.startIndex

    while index < text.endIndex {
      let character = text[index]
      if character == "\\" {
        index = text.index(after: index)
        if index < text.endIndex {
          index = text.index(after: index)
        }
        continue
      }

      if character == "$" {
        let nextIndex = text.index(after: index)
        if nextIndex < text.endIndex, text[nextIndex] == "$" {
          doubleOpen.toggle()
          index = text.index(after: nextIndex)
          continue
        }

        singleOpen.toggle()
      }

      index = text.index(after: index)
    }

    return (singleOpen, doubleOpen)
  }

  private static func deduplicatedFormulaIssues(_ issues: [FormulaIssue]) -> [FormulaIssue] {
    var seen = Set<String>()
    return issues.filter {
      let key = "\($0.sourceId)|\($0.field)|\($0.description)"
      return seen.insert(key).inserted
    }
  }

  private static func deduplicatedImageIssues(_ issues: [ImageIssue]) -> [ImageIssue] {
    var seen = Set<String>()
    return issues.filter {
      let related = $0.relatedImageAssetSourceIds.joined(separator: ",")
      let key = "\($0.sourceId)|\($0.field)|\($0.kind)|\($0.reference)|\(related)"
      return seen.insert(key).inserted
    }
  }

  private static func deduplicatedTableIssues(_ issues: [TableIssue]) -> [TableIssue] {
    var seen = Set<String>()
    return issues.filter {
      let key = "\($0.sourceId)|\($0.field)|\($0.kind)|\($0.description)"
      return seen.insert(key).inserted
    }
  }

  private static func requiredString(
    from fields: [String: ParsedFieldValue],
    key: String
  ) throws -> String {
    guard case .string(let value)? = fields[key] else {
      throw ParseError("missing string field: \(key)")
    }
    return value
  }

  private static func requiredString(
    from fields: [String: ParsedFieldValue],
    keys: [String]
  ) throws -> String {
    for key in keys {
      if case .string(let value)? = fields[key] {
        return value
      }
    }

    throw ParseError("missing string field: \(keys.joined(separator: "|"))")
  }

  private static func stringArray(
    from fields: [String: ParsedFieldValue],
    key: String
  ) -> [String]? {
    guard case .array(let value)? = fields[key] else {
      return nil
    }
    return value
  }

  enum ParsedFieldValue {
    case string(String)
    case array([String])
  }

  struct ParseError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
      self.description = description
    }
  }

  private static func escapeHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}

private extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

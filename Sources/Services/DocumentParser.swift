import Foundation
import PDFKit

class DocumentParser {
    static let shared = DocumentParser()

    private let chunkSize = 400
    private let chunkOverlap = 50
    private let softLimit = 400
    private let hardLimit = 2048

    func parseDocumentAsync(url: URL) async throws -> (text: String, pageCount: Int?) {
        return try parseDocument(url: url)
    }

    func parseDocument(url: URL) throws -> (text: String, pageCount: Int?) {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return try parsePDF(url: url)
        case "docx":
            return try parseDocx(url: url)
        case "txt", "md", "markdown":
            return try parseTxt(url: url)
        default:
            throw ParserError.unsupportedFormat(ext)
        }
    }

    private func parsePDF(url: URL) throws -> (String, Int?) {
        guard let document = PDFDocument(url: url) else {
            throw ParserError.failedToOpen
        }
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                fullText += text + "\n"
            }
        }
        if fullText.isEmpty {
            throw ParserError.emptyDocument
        }
        return (fullText, document.pageCount)
    }

    private func parseDocx(url: URL) throws -> (String, Int?) {
        guard let data = try? Data(contentsOf: url) else {
            throw ParserError.failedToOpen
        }

        let xmlString: String
        do {
            xmlString = try extractDocxXML(from: data)
        } catch {
            throw ParserError.failedToOpen
        }

        let text = stripDocxXML(xmlString)
        if text.isEmpty {
            throw ParserError.emptyDocument
        }
        return (text, nil)
    }

    private func extractDocxXML(from data: Data) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("docx_parse_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zipFile = tempDir.appendingPathComponent("input.docx")
        try data.write(to: zipFile)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zipFile.path, tempDir.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        let xmlPath = tempDir.appendingPathComponent("word/document.xml")
        let xmlData = try Data(contentsOf: xmlPath)
        guard let result = String(data: xmlData, encoding: .utf8) else {
            throw ParserError.failedToOpen
        }
        return result
    }

    private func stripDocxXML(_ xml: String) -> String {
        var text = xml
        text = text.replacingOccurrences(of: "<w:br[^/>]*/>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</w:p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")

        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func parseTxt(url: URL) throws -> (String, Int?) {
        let text = try String(contentsOf: url, encoding: .utf8)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ParserError.emptyDocument
        }
        let lineCount = text.components(separatedBy: "\n").count
        return (text, lineCount)
    }

    func chunkText(_ text: String, type: DocumentType, sourceDocument: String, sourcePath: String) -> [DocumentChunk] {
        switch type {
        case .law:
            return chunkByLawArticles(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        case .legalCase:
            return chunkByCaseParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        case .contract:
            return chunkByContractSections(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        case .misc:
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }
    }

    private func chunkByLawArticles(_ text: String, sourceDocument: String, sourcePath: String) -> [DocumentChunk] {
        let articlePattern = "第[一二三四五六七八九十百千\\d]+条"
        guard let regex = try? NSRegularExpression(pattern: articlePattern) else {
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else {
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }

        var chunks: [DocumentChunk] = []
        var chunkIndex = 0

        for (index, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let start = matchRange.lowerBound
            let end: String.Index
            if index + 1 < matches.count, let nextMatchRange = Range(matches[index + 1].range, in: text) {
                end = nextMatchRange.lowerBound
            } else {
                end = text.endIndex
            }
            var articleText = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if articleText.isEmpty { continue }

            if articleText.count <= softLimit {
                chunks.append(DocumentChunk(
                    text: articleText,
                    index: chunkIndex,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: "law"
                ))
                chunkIndex += 1
            } else {
                let subChunks = splitTextWithSoftLimit(articleText, sourceDocument: sourceDocument, sourcePath: sourcePath, docType: "law", startIndex: chunkIndex)
                chunks.append(contentsOf: subChunks)
                chunkIndex += subChunks.count
            }
        }

        return chunks
    }

    private func chunkByCaseParagraphs(_ text: String, sourceDocument: String, sourcePath: String) -> [DocumentChunk] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }

        var chunks: [DocumentChunk] = []
        var chunkIndex = 0

        for para in paragraphs {
            if para.count <= softLimit {
                chunks.append(DocumentChunk(
                    text: para,
                    index: chunkIndex,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: "case"
                ))
                chunkIndex += 1
            } else {
                let subChunks = splitTextWithSoftLimit(para, sourceDocument: sourceDocument, sourcePath: sourcePath, docType: "case", startIndex: chunkIndex)
                chunks.append(contentsOf: subChunks)
                chunkIndex += subChunks.count
            }
        }

        return chunks
    }

    private func chunkByContractSections(_ text: String, sourceDocument: String, sourcePath: String) -> [DocumentChunk] {
        let chapterPattern = "(第[一二三四五六七八九十]+章|CHAPTER\\s*\\d+|第\\d+条|条\\s*\\d+)"
        guard let regex = try? NSRegularExpression(pattern: chapterPattern, options: .caseInsensitive) else {
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        guard !matches.isEmpty else {
            return chunkByParagraphs(text, sourceDocument: sourceDocument, sourcePath: sourcePath)
        }

        var chunks: [DocumentChunk] = []
        var chunkIndex = 0

        for (i, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let start = matchRange.lowerBound
            let end: String.Index
            if i + 1 < matches.count, let nextRange = Range(matches[i + 1].range, in: text) {
                end = nextRange.lowerBound
            } else {
                end = text.endIndex
            }
            var sectionText = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sectionText.isEmpty { continue }

            if sectionText.count <= softLimit {
                chunks.append(DocumentChunk(
                    text: sectionText,
                    index: chunkIndex,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: "contract"
                ))
                chunkIndex += 1
            } else {
                let subChunks = splitTextWithSoftLimit(sectionText, sourceDocument: sourceDocument, sourcePath: sourcePath, docType: "contract", startIndex: chunkIndex)
                chunks.append(contentsOf: subChunks)
                chunkIndex += subChunks.count
            }
        }

        return chunks
    }

    private func chunkByParagraphs(_ text: String, sourceDocument: String, sourcePath: String) -> [DocumentChunk] {
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 10 }

        var chunks: [DocumentChunk] = []
        var currentChunk = ""
        var chunkIndex = 0

        for para in paragraphs {
            if currentChunk.isEmpty {
                currentChunk = para
            } else if (currentChunk + "\n" + para).count <= chunkSize {
                currentChunk += "\n" + para
            } else {
                chunks.append(DocumentChunk(
                    text: currentChunk,
                    index: chunkIndex,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: "misc"
                ))
                chunkIndex += 1

                let overlapChars = currentChunk.suffix(min(chunkOverlap, currentChunk.count))
                currentChunk = String(overlapChars) + "\n" + para
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(DocumentChunk(
                text: currentChunk,
                index: chunkIndex,
                sourceDocument: sourceDocument,
                sourcePath: sourcePath,
                docType: "misc"
            ))
        }

        return chunks
    }

    private func splitTextWithSoftLimit(_ text: String, sourceDocument: String, sourcePath: String, docType: String, startIndex: Int) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        var remaining = text
        var index = startIndex
        let sentenceDelimiters = ["。", "！", "？", ".", "!", "?"]

        while remaining.count > softLimit {
            var splitPoint = remaining.index(remaining.startIndex, offsetBy: softLimit)

            for delimiter in sentenceDelimiters {
                if let lastDelim = remaining[..<splitPoint].range(of: delimiter, options: .backwards) {
                    splitPoint = lastDelim.upperBound
                    break
                }
            }

            let chunkText = String(remaining[..<splitPoint]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                chunks.append(DocumentChunk(
                    text: chunkText,
                    index: index,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: docType
                ))
                index += 1
            }

            remaining = String(remaining[splitPoint...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty { break }

            if remaining.count <= softLimit {
                let finalChunk = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalChunk.isEmpty {
                    chunks.append(DocumentChunk(
                        text: finalChunk,
                        index: index,
                        sourceDocument: sourceDocument,
                        sourcePath: sourcePath,
                        docType: docType
                    ))
                }
                break
            }
        }

        if !remaining.isEmpty {
            let finalChunk = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalChunk.isEmpty {
                chunks.append(DocumentChunk(
                    text: finalChunk,
                    index: index,
                    sourceDocument: sourceDocument,
                    sourcePath: sourcePath,
                    docType: docType
                ))
            }
        }

        return chunks
    }
}

enum ParserError: Error, LocalizedError {
    case unsupportedFormat(String)
    case failedToOpen
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported format: .\(ext)"
        case .failedToOpen:
            return "Failed to open document"
        case .emptyDocument:
            return "Document is empty"
        }
    }
}

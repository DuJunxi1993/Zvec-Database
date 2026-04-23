import Foundation

// 重复等级
enum DuplicateLevel: Int, Codable {
    case none = 0
    case exact = 1
    case possible = 2

    var displayName: String {
        switch self {
        case .none: return ""
        case .exact: return "重复"
        case .possible: return "可能重复"
        }
    }
}

// 文件名归一化
func normalizeFileName(_ name: String) -> String {
    name.lowercased()
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: ".md", with: "")
        .replacingOccurrences(of: ".markdown", with: "")
        .replacingOccurrences(of: ".pdf", with: "")
        .replacingOccurrences(of: ".docx", with: "")
        .replacingOccurrences(of: ".txt", with: "")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
}

// DocumentType 已移至 KnowledgeBase.swift

struct Document: Identifiable {
    let id: UUID
    let url: URL
    let title: String
    var pageCount: Int?
    var sourcePath: String
    var duplicateLevel: DuplicateLevel = .none
    var fileSize: Int64 = 0
    var type: DocumentType

    init(url: URL, title: String? = nil, type: DocumentType = .law, fileSize: Int64 = 0) {
        self.id = UUID()
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.type = type
        self.sourcePath = url.path
        self.fileSize = fileSize
    }
}

struct DocumentChunk: Identifiable {
    let id: UUID
    let text: String
    let index: Int
    let sourceDocument: String
    let sourcePath: String
    let docType: String

    init(text: String, index: Int, sourceDocument: String, sourcePath: String, docType: String) {
        self.id = UUID()
        self.text = text
        self.index = index
        self.sourceDocument = sourceDocument
        self.sourcePath = sourcePath
        self.docType = docType
    }
}

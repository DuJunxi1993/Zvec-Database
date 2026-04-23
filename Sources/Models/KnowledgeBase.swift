import Foundation

// 文档类型枚举
enum DocumentType: String, Codable, CaseIterable, Comparable {
    case law = "law"
    case legalCase = "case"
    case contract = "contract"
    case misc = "misc"

    static func < (lhs: DocumentType, rhs: DocumentType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .law: return "法律"
        case .legalCase: return "判例"
        case .contract: return "合同"
        case .misc: return "其他"
        }
    }

    var icon: String {
        switch self {
        case .law: return "building.columns"
        case .legalCase: return "scale.3d"
        case .contract: return "doc.text"
        case .misc: return "doc"
        }
    }
}

// 文档记录 - 记录已导入文档的元信息
struct DocumentRecord: Codable, Identifiable {
    let id: UUID
    let title: String
    let type: DocumentType
    let pageCount: Int?
    let chunkCount: Int
    let importedAt: Date
    let sourcePath: String
    var duplicateLevel: DuplicateLevel = .none
    var fileSize: Int64 = 0

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    init(title: String, type: DocumentType, pageCount: Int?, chunkCount: Int, sourcePath: String, fileSize: Int64 = 0) {
        self.id = UUID()
        self.title = title
        self.type = type
        self.pageCount = pageCount
        self.chunkCount = chunkCount
        self.importedAt = Date()
        self.sourcePath = sourcePath
        self.fileSize = fileSize
    }
}

// 知识库
struct KnowledgeBase: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var createdAt: Date
    var updatedAt: Date
    var documentCount: Int
    var chunkCount: Int
    var embeddingModel: String
    var vectorDimension: Int
    var documents: [DocumentRecord]

    var storagePath: String {
        let asciiName = name.data(using: .utf8)!.map { byte -> String in
            let c = Character(UnicodeScalar(byte))
            return c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-") ? String(c) : String(format: "_%02x", byte)
        }.joined()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("legal_kb", isDirectory: true)
            .appendingPathComponent(asciiName, isDirectory: true).path
    }

    init(name: String, description: String = "", embeddingModel: String = "Qwen/Qwen3-Embedding-8B", vectorDimension: Int = 1024) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
        self.documentCount = 0
        self.chunkCount = 0
        self.embeddingModel = embeddingModel
        self.vectorDimension = vectorDimension
        self.documents = []
    }

    var displayInfo: String {
        "文档: \(documentCount) | 块: \(chunkCount) | 维度: \(vectorDimension)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KnowledgeBase, rhs: KnowledgeBase) -> Bool {
        lhs.id == rhs.id
    }

    mutating func removeDocument(id: UUID) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            let removed = documents.remove(at: index)
            documentCount -= 1
            chunkCount -= removed.chunkCount
            updatedAt = Date()
        }
    }
}

// 知识库存储
struct KnowledgeBaseStore: Codable {
    var knowledgeBases: [KnowledgeBase]

    init() {
        self.knowledgeBases = []
    }

    static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Zvec-Database", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("knowledgebases.json")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.storageURL)
        }
    }

    static func load() -> KnowledgeBaseStore {
        guard let data = try? Data(contentsOf: storageURL) else {
            return KnowledgeBaseStore()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let store = try? decoder.decode(KnowledgeBaseStore.self, from: data) {
            return store
        }
        // JSON exists but decoding failed - backup corrupted file
        let backupURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("knowledgebases_backup_\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: backupURL)
        return KnowledgeBaseStore()
    }
}

import Foundation

enum EmbeddingProvider: String, CaseIterable, Identifiable, Codable {
    case openai = "OpenAI"
    case siliconFlow = "SiliconFlow"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .custom: return ""
        }
    }

    var models: [String] {
        switch self {
        case .openai:
            return ["text-embedding-4", "text-embedding-3-large", "text-embedding-3-small"]
        case .siliconFlow:
            return [
                "Qwen/Qwen3-Embedding-8B",
                "Qwen/Qwen3-Embedding-0.6B",
                "netease-youdao/bce-embedding-base_v1",
                "BAAI/bge-large-zh-v1.5",
                "BAAI/bge-m3"
            ]
        case .custom:
            return []
        }
    }
}

struct EmbeddingConfig: Codable {
    var provider: EmbeddingProvider
    var apiKey: String
    var baseURL: String
    var model: String
    var customVectorDimension: Int

    init(provider: EmbeddingProvider = .siliconFlow, apiKey: String = "", model: String = "Qwen/Qwen3-Embedding-8B", customVectorDimension: Int = 1024) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = provider.defaultBaseURL
        self.model = model
        self.customVectorDimension = customVectorDimension
    }

    var vectorDimension: Int {
        customVectorDimension
    }

    var defaultDimensionForModel: Int {
        if model.contains("bce-embedding") { return 768 }
        if model.contains("Qwen3-Embedding-8B") { return 1024 }
        if model.contains("Qwen3-Embedding-0.6B") { return 1024 }
        if model.contains("bge-large-zh-v1.5") { return 1024 }
        if model.contains("bge-m3") { return 1024 }
        if model.contains("text-embedding-3-small") { return 1536 }
        if model.contains("text-embedding-3-large") { return 3072 }
        if model.contains("text-embedding-4") { return 1536 }
        return 1024
    }

    var isValid: Bool {
        !apiKey.isEmpty && !baseURL.isEmpty && !model.isEmpty
    }

    var supportsCustomDimension: Bool {
        true
    }

    static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Zvec-Database", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("embedding_config.json")
    }

    func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.storageURL)
        }
    }

    static func load() -> EmbeddingConfig {
        guard let data = try? Data(contentsOf: storageURL) else {
            return EmbeddingConfig()
        }
        return (try? JSONDecoder().decode(EmbeddingConfig.self, from: data)) ?? EmbeddingConfig()
    }
}

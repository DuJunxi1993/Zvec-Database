import Foundation

class EmbeddingService: ObservableObject {
    static let shared = EmbeddingService()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private var config: EmbeddingConfig

    init() {
        self.config = EmbeddingConfig.load()
    }

    func updateConfig(_ config: EmbeddingConfig) {
        self.config = config
    }

    func getConfig() -> EmbeddingConfig {
        return config
    }

    func testConnection() async -> Bool {
        guard config.isValid else {
            errorMessage = "配置不完整"
            return false
        }

        let testText = "测试连接"
        let result = await generateEmbedding(text: testText)

        switch result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = error.localizedDescription
            return false
        }
    }

    func generateEmbedding(text: String) async -> Result<[Float], EmbeddingError> {
        guard config.isValid else {
            return .failure(.invalidConfig)
        }

        guard let url = URL(string: "\(config.baseURL)/embeddings") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "input": text
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(.serializationError)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.networkError)
            }

            if httpResponse.statusCode != 200 {
                if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorDict["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return .failure(.apiError(message))
                }
                return .failure(.apiError("HTTP \(httpResponse.statusCode)"))
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let embeddings = json["data"] as? [[String: Any]],
                  let first = embeddings.first,
                  let embedding = first["embedding"] as? [Double] else {
                return .failure(.parseError)
            }

            return .success(embedding.map { Float($0) })
        } catch {
            return .failure(.networkError)
        }
    }

    func generateEmbeddings(texts: [String], progress: @escaping (Int, Int) -> Void) async -> Result<[[Float]], EmbeddingError> {
        var allEmbeddings: [[Float]] = []
        let total = texts.count

        for (index, text) in texts.enumerated() {
            progress(index + 1, total)

            let result = await generateEmbedding(text: text)
            switch result {
            case .success(let embedding):
                allEmbeddings.append(embedding)
            case .failure(let error):
                return .failure(error)
            }
        }

        return .success(allEmbeddings)
    }
}

enum EmbeddingError: Error, LocalizedError {
    case invalidConfig
    case invalidURL
    case serializationError
    case networkError
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidConfig:
            return "API 配置不完整"
        case .invalidURL:
            return "无效的 API URL"
        case .serializationError:
            return "请求序列化失败"
        case .networkError:
            return "网络请求失败"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .parseError:
            return "响应解析失败"
        }
    }
}

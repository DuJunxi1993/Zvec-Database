import SwiftUI

enum MCPPlatform: String, CaseIterable, Identifiable {
    case qoder = "Qoder"
    case claudeDesktop = "Claude Desktop"
    case claudeCode = "Claude Code"
    case opencode = "OpenCode"
    case astrbot = "AstrBot"
    case custom = "Custom"

    var id: String { rawValue }

    var schemaURL: String {
        switch self {
        case .qoder: return "https://qoder.ai/config.json"
        case .claudeDesktop: return "https://anthropic.com/claude-code/config.json"
        case .claudeCode: return "https://anthropic.com/claude-code/config.json"
        case .opencode: return "https://opencode.ai/config.json"
        case .astrbot: return "https://astrbot.app/config.json"
        case .custom: return ""
        }
    }

    var configServerName: String {
        switch self {
        case .qoder: return "zvec-mcp"
        case .claudeDesktop: return "zvec-mcp"
        case .claudeCode: return "zvec-mcp"
        case .opencode: return "zvec-legal"
        case .astrbot: return "zvec-mcp"
        case .custom: return "zvec-mcp"
        }
    }

    var useCommandArgsFormat: Bool {
        switch self {
        case .claudeDesktop: return false
        default: return true
        }
    }

    var supportsFullEnv: Bool {
        switch self {
        case .claudeDesktop: return false
        default: return true
        }
    }

    var installCommand: String {
        switch self {
        case .qoder: return "qodercli mcp add zvec-mcp uvx zvec-mcp-server -e OPENAI_API_KEY=xxx ..."
        case .claudeDesktop: return "claude mcp add zvec-mcp uvx zvec-mcp-server ..."
        case .claudeCode: return "claude mcp add zvec-mcp uvx zvec-mcp-server -e OPENAI_API_KEY=xxx ..."
        case .opencode: return "不支持 CLI 安装，请手动添加配置"
        case .astrbot: return "AstrBot MCP 设置页面手动添加"
        case .custom: return "根据你的平台文档配置"
        }
    }
}

struct MCPSettingsView: View {
    @StateObject private var serverService = MCPServerService.shared
    @State private var config: EmbeddingConfig = EmbeddingConfig.load()
    @State private var mcpConfig: String = ""
    @State private var copySuccess = false
    @State private var selectedPlatform: MCPPlatform = .qoder
    @State private var customSchemaURL: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                Divider()

                serverStatusSection
                Divider()

                descriptionSection
                Divider()

                platformSection
                Divider()

                configExportSection
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: loadConfig)
        .onChange(of: config.apiKey) { _, _ in generateConfig() }
        .onChange(of: config.baseURL) { _, _ in generateConfig() }
        .onChange(of: config.model) { _, _ in generateConfig() }
        .onChange(of: selectedPlatform) { _, _ in generateConfig() }
        .onChange(of: customSchemaURL) { _, _ in generateConfig() }
    }

    private var headerView: some View {
        Text("MCP 配置")
            .font(.title)
            .fontWeight(.bold)
    }

    private var serverStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server 状态")
                .font(.headline)

            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                Text(serverService.status.displayText)
                    .font(.body)

                Spacer()

                if serverService.status == .starting {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(serverService.status == .running ? "停止 Server" : "启动 Server") {
                    if serverService.status == .running {
                        serverService.stopServer()
                    } else {
                        serverService.startServer()
                    }
                }
                .disabled(serverService.status == .starting)
            }

            if case .error(let message) = serverService.status {
                Text("错误信息: \(message)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    private var statusColor: Color {
        switch serverService.status {
        case .running: return .green
        case .stopped, .unknown: return .gray
        case .starting: return .yellow
        case .error: return .red
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用说明")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. 启动 Server 后，复制下方配置到你的 AI Agent MCP 配置文件中")
                Text("2. 支持 Qoder、Claude Code、OpenCode、AstrBot 等支持 MCP 协议的 Agent")
                Text("3. 确保已通过 `uvx zvec-mcp-server` 安装 MCP Server")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目标平台")
                .font(.headline)

            HStack {
                Text("Platform:")
                Picker("", selection: $selectedPlatform) {
                    ForEach(MCPPlatform.allCases) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                .frame(width: 180)

                if selectedPlatform == .custom {
                    TextField("https://your-platform/config.json", text: $customSchemaURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
            }

            Text("安装命令: \(selectedPlatform.installCommand)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var configExportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MCP 配置")
                    .font(.headline)
                Spacer()
                Button("复制配置") {
                    copyToClipboard()
                }
                .buttonStyle(.borderedProminent)
                .disabled(copySuccess)

                if copySuccess {
                    Text("已复制!")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            ScrollView {
                Text(mcpConfig)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 300)

            VStack(alignment: .leading, spacing: 8) {
                Text("配置说明:")
                    .font(.headline)
                Text("• command/args: 使用 uvx 运行 MCP Server")
                Text("• env: API 配置环境变量（OPENAI_API_KEY 必填）")
                Text("• \(selectedPlatform == .custom ? "请确保 schema URL 正确" : "schema: \(selectedPlatform.schemaURL.isEmpty ? "自定义" : selectedPlatform.schemaURL)")")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top)
        }
    }

    private func loadConfig() {
        config = EmbeddingConfig.load()
        generateConfig()
    }

    private func generateConfig() {
        let escapedKey = config.apiKey.isEmpty ? "your-api-key" : config.apiKey
        let schemaURL = selectedPlatform == .custom ? customSchemaURL : selectedPlatform.schemaURL
        let serverName = selectedPlatform.configServerName

        if selectedPlatform.useCommandArgsFormat {
            mcpConfig = """
            {
              "$schema": "\(schemaURL)",
              "mcp": {
                "\(serverName)": {
                  "type": "local",
                  "command": ["uvx", "zvec-mcp-server"],
                  "environment": {
                    "OPENAI_API_KEY": "\(escapedKey)",
                    "OPENAI_BASE_URL": "\(config.baseURL)",
                    "OPENAI_EMBEDDING_MODEL": "\(config.model)"
                  },
                  "enabled": true
                }
              }
            }
            """
        } else {
            mcpConfig = """
            {
              "$schema": "\(schemaURL)",
              "mcpServers": {
                "\(serverName)": {
                  "command": "uvx",
                  "args": ["zvec-mcp-server"],
                  "env": {
                    "OPENAI_API_KEY": "\(escapedKey)"
                  }
                }
              }
            }
            """
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(mcpConfig, forType: .string)

        copySuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copySuccess = false
        }
    }
}

#Preview {
    MCPSettingsView()
}

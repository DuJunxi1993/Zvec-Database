import SwiftUI

struct SettingsView: View {
    @State private var config: EmbeddingConfig = EmbeddingConfig.load()
    @State private var isTesting = false
    @State private var testResult: Bool?
    @State private var showingSaveAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                Divider()

                apiConfigSection
                Divider()

                modelConfigSection
                Divider()

                actionButtons
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: loadConfig)
    }

    private var headerView: some View {
        Text("设置")
            .font(.title)
            .fontWeight(.bold)
    }

    private var apiConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API 配置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Provider:")
                    Picker("", selection: $config.provider) {
                        ForEach(EmbeddingProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .frame(width: 200)
                    .onChange(of: config.provider) { _, newValue in
                        config.baseURL = newValue.defaultBaseURL
                    }
                }

                HStack {
                    Text("API Key:")
                    SecureField("输入 API Key", text: $config.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Base URL:")
                    TextField("https://api.example.com/v1", text: $config.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var modelConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型配置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Embedding Model:")
                    .foregroundColor(.secondary)

                if config.provider.models.isEmpty {
                    HStack {
                        TextField("自定义模型名称", text: $config.model)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    ForEach(config.provider.models, id: \.self) { model in
                        HStack {
                            RadioButton(
                                title: model,
                                isSelected: config.model == model
                            ) {
                                config.model = model
                            }
                        }
                    }
                }

                HStack {
                    Text("向量维度:")
                    TextField("1024", text: Binding(
                        get: { String(config.customVectorDimension) },
                        set: { config.customVectorDimension = Int($0) ?? 1024 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("（不填则自动检测）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("提示: \(config.defaultDimensionForModel) 为当前模型的默认维度，实际维度以首次导入时自动检测为准")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("测试连接") {
                testConnection()
            }
            .disabled(config.apiKey.isEmpty || isTesting)

            if isTesting {
                ProgressView()
                    .scaleEffect(0.8)
            }

            if let result = testResult {
                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result ? .green : .red)
                Text(result ? "连接成功" : "连接失败")
                    .foregroundColor(result ? .green : .red)
            }

            Spacer()

            Button("保存配置") {
                saveConfig()
            }
            .buttonStyle(.borderedProminent)
        }
        .alert("保存成功", isPresented: $showingSaveAlert) {
            Button("确定") { }
        } message: {
            Text("API 配置已保存")
        }
    }

    private func loadConfig() {
        config = EmbeddingConfig.load()
    }

    private func saveConfig() {
        config.save()
        EmbeddingService.shared.updateConfig(config)
        showingSaveAlert = true
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        config.save()
        EmbeddingService.shared.updateConfig(config)

        Task {
            let success = await EmbeddingService.shared.testConnection()
            await MainActor.run {
                isTesting = false
                testResult = success
            }
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                Text(title)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}

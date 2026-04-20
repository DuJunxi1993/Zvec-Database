import SwiftUI
import UniformTypeIdentifiers
import AppKit

// 导入结果记录
struct ImportResult: Identifiable {
    let id: UUID
    let title: String
    let status: ImportStatus
    let chunkCount: Int
    let errorMessage: String?

    enum ImportStatus {
        case pending, importing, success, failed
    }
}

// Node.js 脚本输出结构
struct ImportScriptOutput: Decodable {
    let success: Bool
    let imported: Int?
    let failed: Int?
    let dimension: Int?
    let documents: [ImportDocResult]?
    let error: String?
}

struct ImportDocResult: Decodable {
    let title: String
    let chunks: Int?
    let status: String
    let error: String?
}

struct DocumentImportView: View {
    @State private var selectedDocuments: [Document] = []
    @State private var selectedKB: KnowledgeBase?
    @State private var knowledgeBases: [KnowledgeBase] = []
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int) = (0, 0)
    @State private var importStatusMessage: String = ""
    @State private var previewChunks: [DocumentChunk] = []
    @State private var showingPreview = false
    @State private var errorMessage: String?
    @State private var showingNewKBDialog = false
    @State private var newKBName = ""
    @State private var importResults: [ImportResult] = []
    @State private var selectedDocumentType: DocumentType = .law

    // 防重复状态
    @State private var showingDuplicateAlert = false
    @State private var duplicateDocsInKB: [Document] = []
    @State private var cleanDocsForImport: [Document] = []
    @State private var skipDuplicatePromptThisSession = false

    private let parser = DocumentParser.shared
    private let zvecService = ZvecService.shared

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            if isImporting {
                Divider()
                progressView
            }
            if !importResults.isEmpty {
                Divider()
                importResultsView
            }
            if let error = errorMessage {
                Divider()
                errorView(error)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: loadKnowledgeBases)
        .onChange(of: selectedDocumentType) { _, newType in
            for i in selectedDocuments.indices {
                selectedDocuments[i].userSelectedType = newType
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf, .text, UTType(filenameExtension: "docx")!, UTType(filenameExtension: "md")!, UTType(filenameExtension: "markdown")!], allowsMultipleSelection: true) { result in
            handleFileSelection(result)
        }
        .alert("新建知识库", isPresented: $showingNewKBDialog) {
            TextField("知识库名称", text: $newKBName)
            Button("取消", role: .cancel) { }
            Button("创建") { createKnowledgeBase() }
        }
        .alert("发现重复文档", isPresented: $showingDuplicateAlert) {
            Button("全部覆盖", role: .destructive) {
                performImportWithOverwrite(duplicates: duplicateDocsInKB, cleanDocs: cleanDocsForImport)
            }
            Button("全部跳过") {
                performImportWithSkip(cleanDocs: cleanDocsForImport)
            }
            Button("继续导入（保留重复）") {
                performImportWithKeepAll()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("以下 \(duplicateDocsInKB.count) 个文档可能已存在于知识库中：\n\(duplicateDocsInKB.prefix(5).map { "• \($0.title)" }.joined(separator: "\n"))\(duplicateDocsInKB.count > 5 ? "\n... 等 \(duplicateDocsInKB.count - 5) 个" : "")")
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文档导入")
                .font(.title)
                .fontWeight(.bold)
            HStack(spacing: 12) {
                Text("目标知识库:")
                Picker("", selection: $selectedKB) {
                    Text("请选择...").tag(nil as KnowledgeBase?)
                    ForEach(knowledgeBases) { kb in
                        Text(kb.name).tag(kb as KnowledgeBase?)
                    }
                }
                .frame(width: 200)
                Button("新建") {
                    showingNewKBDialog = true
                }
                Spacer()
                Text("文档类型:")
                Picker("", selection: $selectedDocumentType) {
                    Text("法律").tag(DocumentType.law)
                    Text("判例").tag(DocumentType.legalCase)
                    Text("合同").tag(DocumentType.contract)
                    Text("其他").tag(DocumentType.misc)
                }
                .frame(width: 100)
            }
        }
        .padding()
    }

    private var contentView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button("选择文件") { showingFilePicker = true }
                Button("选择文件夹") { selectFolder() }
                Spacer()
                if !selectedDocuments.isEmpty {
                    Button("清空") {
                        selectedDocuments.removeAll()
                        previewChunks.removeAll()
                        importResults.removeAll()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)

            if selectedDocuments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择文件或文件夹开始导入")
                        .foregroundColor(.secondary)
                    Text("或拖拽文件到此处")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                documentListView
                    .frame(minHeight: 200)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }
            }

            if showingPreview && !previewChunks.isEmpty {
                chunkPreviewView
            }

            if selectedKB != nil && !selectedDocuments.isEmpty && !isImporting {
                HStack {
                    Spacer()
                    Button("开始导入") { startImport() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
            }
        }
        .padding(.vertical)
    }

    private var documentListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选文件 (\(selectedDocuments.count))")
                    .font(.headline)
                Spacer()
                Button("预览分块") { loadPreviewChunks() }
                    .disabled(selectedDocuments.isEmpty)
            }
            .padding(.horizontal)

            List {
                ForEach(selectedDocuments) { doc in
                    HStack {
                        Image(systemName: doc.userSelectedType.icon)
                            .foregroundColor(doc.duplicateLevel == .none ? .blue : .orange)
                        Text(doc.title)
                            .lineLimit(1)
                        if doc.duplicateLevel != .none {
                            Text("⚠️ \(doc.duplicateLevel.displayName)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Text(doc.userSelectedType.displayName)
                            .foregroundColor(.secondary)
                        if let pages = doc.pageCount {
                            Text("\(pages) 页")
                                .foregroundColor(.secondary)
                        }
                        Button(action: { removeDocument(doc) }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
            .padding(.horizontal)
        }
    }

    private var chunkPreviewView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分块预览")
                    .font(.headline)
                Spacer()
                Button("关闭") { showingPreview = false }
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(previewChunks.prefix(5).enumerated()), id: \.element.id) { index, chunk in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("块 \(index + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(chunk.text.prefix(200)) + (chunk.text.count > 200 ? "..." : ""))
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    if previewChunks.count > 5 {
                        Text("... 还有 \(previewChunks.count - 5) 个块")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        }
    }

    private var progressView: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(importProgress.current), total: Double(max(importProgress.total, 1)))
                .padding(.horizontal)
            Text(importStatusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var importResultsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("导入结果")
                    .font(.headline)
                Spacer()
                Button("清除结果") { importResults.removeAll() }
            }
            .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(importResults) { result in
                        HStack {
                            Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.status == .success ? .green : .red)
                            Text(result.title)
                                .lineLimit(1)
                            Spacer()
                            if result.chunkCount > 0 {
                                Text("\(result.chunkCount) 块")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let error = result.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .padding(.vertical)
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .foregroundColor(.red)
            Spacer()
            Button("关闭") { errorMessage = nil }
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }

    private func loadKnowledgeBases() {
        knowledgeBases = KnowledgeBaseStore.load().knowledgeBases
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            addDocuments(from: urls)
        case .failure:
            errorMessage = "选择文件失败"
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task {
            var urls: [URL] = []
            for provider in providers {
                do {
                    let items = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                    if let data = items as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                } catch {
                    continue
                }
            }
            if !urls.isEmpty {
                await MainActor.run {
                    addDocuments(from: urls)
                }
            }
        }
        return true
    }

    private func addDocuments(from urls: [URL]) {
        let currentType = selectedDocumentType
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            // iCloud 文件可能未下载，先触发下载
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs?[.size] as? Int64 ?? 0

            let doc = Document(url: url, fileSize: fileSize, userSelectedType: currentType)

            // 精确路径匹配 → 跳过
            if selectedDocuments.contains(where: { $0.url == url }) {
                continue
            }

            // 检测选择列表中的重复（精确/模糊）
            var duplicateLevel = DuplicateLevel.none
            let normalizedNew = normalizeFileName(doc.title)

            for existing in selectedDocuments {
                let normalizedExist = normalizeFileName(existing.title)
                if normalizedNew == normalizedExist {
                    duplicateLevel = .exact
                    break
                } else if normalizedNew.count >= 10 && normalizedExist.count >= 10
                         && normalizedNew.prefix(10) == normalizedExist.prefix(10) {
                    duplicateLevel = .possible
                }
            }

            var newDoc = doc
            newDoc.duplicateLevel = duplicateLevel
            selectedDocuments.append(newDoc)
        }
    }

    private func removeDocument(_ doc: Document) {
        selectedDocuments.removeAll { $0.id == doc.id }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择包含文档的文件夹"

        if panel.runModal() == .OK, let url = panel.url {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
            let documentURLs = contents.filter { fileURL in
                let ext = fileURL.pathExtension.lowercased()
                return ["pdf", "docx", "txt", "md", "markdown"].contains(ext)
            }

            let currentType = selectedDocumentType
            for docUrl in documentURLs {
                guard docUrl.startAccessingSecurityScopedResource() else { continue }
                defer { docUrl.stopAccessingSecurityScopedResource() }

                let attrs = try? FileManager.default.attributesOfItem(atPath: docUrl.path)
                let fileSize = attrs?[.size] as? Int64 ?? 0
                let doc = Document(url: docUrl, fileSize: fileSize, userSelectedType: currentType)
                if !selectedDocuments.contains(where: { $0.url == docUrl }) {
                    selectedDocuments.append(doc)
                }
            }
        }
    }

    private func loadPreviewChunks() {
        guard let firstDoc = selectedDocuments.first else { return }
        isImporting = true
        importProgress = (0, 1)
        Task {
            let result: (String, Int?, [DocumentChunk]) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let (text, pages) = try DocumentParser.shared.parseDocument(url: firstDoc.url)
                        let chunks = DocumentParser.shared.chunkText(text, type: firstDoc.userSelectedType ?? firstDoc.type, sourceDocument: firstDoc.title, sourcePath: firstDoc.sourcePath)
                        continuation.resume(returning: (text, pages, chunks))
                    } catch {
                        continuation.resume(returning: ("", nil, []))
                    }
                }
            }
            await MainActor.run {
                if !result.0.isEmpty {
                    var updatedDoc = firstDoc
                    updatedDoc.pageCount = result.1
                    if let index = selectedDocuments.firstIndex(where: { $0.id == firstDoc.id }) {
                        selectedDocuments[index] = updatedDoc
                    }
                    previewChunks = result.2
                    showingPreview = true
                } else {
                    errorMessage = "预览失败: 文档为空或无法解析"
                }
                isImporting = false
                importProgress = (0, 0)
            }
        }
    }

    private func createKnowledgeBase() {
        guard !newKBName.isEmpty else { return }
        let config = EmbeddingConfig.load()
        let kb = KnowledgeBase(name: newKBName, embeddingModel: config.model, vectorDimension: config.vectorDimension)
        var store = KnowledgeBaseStore.load()
        store.knowledgeBases.append(kb)
        store.save()
        knowledgeBases = store.knowledgeBases
        selectedKB = kb
        newKBName = ""
    }

    private func startImport() {
        guard let kb = selectedKB, !selectedDocuments.isEmpty else { return }

        // 检查 KB 中是否有重复
        var kbDuplicates: [Document] = []
        var cleanDocs: [Document] = []

        for doc in selectedDocuments {
            let normalizedNew = normalizeFileName(doc.title)
            let isDuplicate = kb.documents.contains { existing in
                let normalizedExist = normalizeFileName(existing.title)
                return normalizedNew == normalizedExist
                    || (normalizedNew.count >= 10 && normalizedExist.count >= 10
                        && normalizedNew.prefix(10) == normalizedExist.prefix(10))
            }
            if isDuplicate {
                kbDuplicates.append(doc)
            } else {
                cleanDocs.append(doc)
            }
        }

        if !kbDuplicates.isEmpty && !skipDuplicatePromptThisSession {
            duplicateDocsInKB = kbDuplicates
            cleanDocsForImport = cleanDocs
            showingDuplicateAlert = true
            return
        }

        performImportWithKeepAll()
    }

    private func performImportWithOverwrite(duplicates: [Document], cleanDocs: [Document]) {
        skipDuplicatePromptThisSession = true
        // 覆盖模式：只导入新文档（已在 KB 中的会被跳过）
        // 实际覆盖通过"跳过"重复来实现，下次用户可手动删除旧文档后重新导入
        if cleanDocs.isEmpty && !duplicates.isEmpty {
            isImporting = false
            errorMessage = "所有文档均已存在，请先删除旧文档后再导入"
            return
        }
        performImportWithSkip(cleanDocs: cleanDocs)
    }

    private func performImportWithSkip(cleanDocs: [Document]) {
        skipDuplicatePromptThisSession = true
        if cleanDocs.isEmpty {
            isImporting = false
            errorMessage = "没有需要导入的文档"
            return
        }
        performImport(documents: cleanDocs, overwriteIds: [])
    }

    private func performImportWithKeepAll() {
        performImport(documents: selectedDocuments, overwriteIds: [])
    }

    private func performImport(documents: [Document], overwriteIds: [UUID] = []) {
        self.overwriteIds = overwriteIds
        guard let kb = selectedKB, !documents.isEmpty else { return }
        isImporting = true
        importProgress = (0, documents.count)
        importStatusMessage = "正在解析文档..."
        importResults.removeAll()

        let docsToProcess = documents
        let kbForImport = kb
        let config = EmbeddingConfig.load()
        let kbPath = ZvecService.shared.kbStoragePath(for: kbForImport.name)

        Task {
            // === 阶段 1: 解析所有文档 ===
            let parseResult: ([(Document, [DocumentChunk])], [ImportResult]) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var parsed: [(Document, [DocumentChunk])] = []
                    var results: [ImportResult] = []

                    for doc in docsToProcess {
                        do {
                            let (text, _) = try DocumentParser.shared.parseDocument(url: doc.url)
                            let docChunks = DocumentParser.shared.chunkText(text, type: doc.userSelectedType ?? doc.type, sourceDocument: doc.title, sourcePath: doc.sourcePath)
                            parsed.append((doc, docChunks))
                            results.append(ImportResult(
                                id: UUID(), title: doc.title, status: .pending, chunkCount: docChunks.count, errorMessage: nil
                            ))
                        } catch {
                            results.append(ImportResult(
                                id: UUID(), title: doc.title, status: .failed, chunkCount: 0, errorMessage: error.localizedDescription
                            ))
                        }
                    }
                    continuation.resume(returning: (parsed, results))
                }
            }

            let parsedDocs = parseResult.0
            importResults = parseResult.1
            guard !parsedDocs.isEmpty else {
                isImporting = false
                importStatusMessage = ""
                return
            }

            // === 阶段 2: 分批调用 import.js ===
            let batchSize = 5
            var totalImported = 0
            var detectedDim: Int?

            guard let scriptPath = copyScriptToTemp("import.js"),
                  let optimizeScriptPath = copyScriptToTemp("optimize.js") else {
                await MainActor.run {
                    errorMessage = "无法获取脚本文件"
                    isImporting = false
                    importStatusMessage = ""
                }
                return
            }

            let nodePath = ZvecService.shared.getNodePath()
            let npmGlobalPath = ZvecService.shared.getNpmGlobalPath()

            var batchIndex = 0
            while batchIndex * batchSize < parsedDocs.count {
                let start = batchIndex * batchSize
                let end = min(start + batchSize, parsedDocs.count)
                let batch = Array(parsedDocs[start..<end])

                await MainActor.run {
                    importProgress = (start, docsToProcess.count)
                    importStatusMessage = "正在处理文档分块 (第 \(start + 1)-\(end) 个文档，共 \(docsToProcess.count) 个)"
                }

                let allChunks = batch.flatMap { $0.1 }
                let chunksData = allChunks.map { chunk -> [String: Any] in
                    ["id": chunk.id.uuidString, "text": chunk.text, "type": chunk.docType, "source": chunk.sourcePath, "title": chunk.sourceDocument]
                }

                guard let jsonData = try? JSONSerialization.data(withJSONObject: chunksData),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continue
                }

                let docsTempFile = FileManager.default.temporaryDirectory.appendingPathComponent("import_docs_\(UUID().uuidString).json")
                if let e = try? jsonString.write(to: docsTempFile, atomically: true, encoding: .utf8) { _ = e }
                defer { try? FileManager.default.removeItem(at: docsTempFile) }

                let shellScriptContent = """
                #!/bin/bash
                NODE_PATH='\(npmGlobalPath)' '\(nodePath)' '\(scriptPath)' \
                    --kb-path '\(kbPath.path)' \
                    --docs-file '\(docsTempFile.path)' \
                    --api-key '\(config.apiKey)' \
                    --base-url '\(config.baseURL)' \
                    --model '\(config.model)'
                """

                let tempShellScript = FileManager.default.temporaryDirectory.appendingPathComponent("run_import_\(UUID().uuidString).sh")
                if let e = try? shellScriptContent.write(to: tempShellScript, atomically: true, encoding: .utf8) { _ = e }
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempShellScript.path)
                defer { try? FileManager.default.removeItem(at: tempShellScript) }

                await MainActor.run {
                    importStatusMessage = "正在调用 Embedding 模型 (第 \(batchIndex * batchSize + 1)-\(min((batchIndex + 1) * batchSize, docsToProcess.count)) 个文档)"
                }

                let scriptOutput: (stdout: String, stderr: String, exitCode: Int32) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/bin/bash")
                        task.arguments = [tempShellScript.path]
                        let outputPipe = Pipe()
                        let errorPipe = Pipe()
                        task.standardOutput = outputPipe
                        task.standardError = errorPipe
                        do {
                            try task.run()
                            task.waitUntilExit()
                            let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                            continuation.resume(returning: (String(data: outData, encoding: .utf8) ?? "", String(data: errData, encoding: .utf8) ?? "", task.terminationStatus))
                        } catch {
                            continuation.resume(returning: ("", error.localizedDescription, -1))
                        }
                    }
                }

                if let dataJson = scriptOutput.stdout.data(using: .utf8),
                   let result = try? JSONDecoder().decode(ImportScriptOutput.self, from: dataJson) {
                    totalImported += result.imported ?? 0
                    if let dim = result.dimension { detectedDim = dim }

                    for i in 0..<importResults.count {
                        if let docResult = result.documents?.first(where: { $0.title == importResults[i].title }) {
                            importResults[i] = ImportResult(
                                id: importResults[i].id,
                                title: importResults[i].title,
                                status: docResult.status == "success" ? .success : .failed,
                                chunkCount: docResult.chunks ?? 0,
                                errorMessage: docResult.error
                            )
                        }
                    }
                }

                // === 调用 optimize ===
                await MainActor.run {
                    importStatusMessage = "正在优化索引..."
                }

                let optimizeShell = """
                #!/bin/bash
                NODE_PATH='\(npmGlobalPath)' '\(nodePath)' '\(optimizeScriptPath)' --kb-path '\(kbPath.path)'
                """
                let optTempScript = FileManager.default.temporaryDirectory.appendingPathComponent("run_optimize_\(UUID().uuidString).sh")
                if let e = try? optimizeShell.write(to: optTempScript, atomically: true, encoding: .utf8) { _ = e }
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: optTempScript.path)
                defer { try? FileManager.default.removeItem(at: optTempScript) }

                let _: (String, String, Int32) = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/bin/bash")
                        task.arguments = [optTempScript.path]
                        let outPipe = Pipe()
                        task.standardOutput = outPipe
                        task.standardError = Pipe()
                        do {
                            try task.run()
                            task.waitUntilExit()
                            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                            continuation.resume(returning: (String(data: outData, encoding: .utf8) ?? "", "", task.terminationStatus))
                        } catch {
                            continuation.resume(returning: ("", error.localizedDescription, -1))
                        }
                    }
                }

                // 批次间延迟
                if batchIndex < (parsedDocs.count / batchSize) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                batchIndex += 1
            }

            // === 更新知识库元数据 ===
            await MainActor.run {
                importStatusMessage = "正在更新元数据..."
                if totalImported > 0 || !overwriteIds.isEmpty {
                    var store = KnowledgeBaseStore.load()
                    if let index = store.knowledgeBases.firstIndex(where: { $0.id == kbForImport.id }) {
                        // 删除被覆盖的文档记录
                        if !overwriteIds.isEmpty {
                            for oid in overwriteIds {
                                if let docIndex = store.knowledgeBases[index].documents.firstIndex(where: { $0.id == oid }) {
                                    store.knowledgeBases[index].documents.remove(at: docIndex)
                                    store.knowledgeBases[index].documentCount -= 1
                                }
                            }
                        }

                        var successDocCount = 0
                        for (doc, _) in parsedDocs {
                            let result = importResults.first(where: { $0.title == doc.title })
                            let actualChunkCount = result?.chunkCount ?? 0
                            let record = DocumentRecord(
                                title: doc.title, type: doc.userSelectedType ?? .law, pageCount: doc.pageCount, chunkCount: actualChunkCount, sourcePath: doc.sourcePath, fileSize: doc.fileSize, userSelectedType: doc.userSelectedType ?? .law
                            )
                            store.knowledgeBases[index].documents.append(record)
                            if result?.status == .success {
                                successDocCount += 1
                            }
                        }
                        store.knowledgeBases[index].documentCount += successDocCount
                        store.knowledgeBases[index].chunkCount += totalImported
                        if let dim = detectedDim {
                            store.knowledgeBases[index].vectorDimension = dim
                        }
                        store.knowledgeBases[index].updatedAt = Date()
                        store.save()
                        knowledgeBases = store.knowledgeBases
                    }
                }
                importProgress = (docsToProcess.count, docsToProcess.count)
                importStatusMessage = ""
                isImporting = false
                selectedDocuments.removeAll()
                previewChunks.removeAll()
            }
        }
    }

    @State private var overwriteIds: [UUID] = []

    private func copyScriptToTemp(_ scriptName: String) -> String? {
        var bundleScriptURL: URL?

        if let resourcePath = Bundle.main.resourcePath {
            let rootURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(scriptName)
            if FileManager.default.fileExists(atPath: rootURL.path) {
                bundleScriptURL = rootURL
            }
        }

        if bundleScriptURL == nil, let resourcePath = Bundle.main.resourcePath {
            let scriptsURL = URL(fileURLWithPath: resourcePath).appendingPathComponent("scripts/\(scriptName)")
            if FileManager.default.fileExists(atPath: scriptsURL.path) {
                bundleScriptURL = scriptsURL
            }
        }

        if bundleScriptURL == nil {
            if let path = Bundle.main.path(forResource: scriptName, ofType: nil) {
                bundleScriptURL = URL(fileURLWithPath: path)
            }
        }

        if bundleScriptURL == nil {
            if let path = Bundle.main.path(forResource: scriptName, ofType: nil, inDirectory: "scripts") {
                bundleScriptURL = URL(fileURLWithPath: path)
            }
        }

        guard let scriptURL = bundleScriptURL else {
            print("Script not found: \(scriptName)")
            return nil
        }

        guard let scriptContent = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            print("Failed to read script at: \(scriptURL.path)")
            return nil
        }

        let tempDir = FileManager.default.temporaryDirectory
        let tempScriptURL = tempDir.appendingPathComponent(scriptName)

        do {
            try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
            return tempScriptURL.path
        } catch {
            print("Failed to write temp script: \(error)")
            return nil
        }
    }
}

#Preview {
    DocumentImportView()
}

import SwiftUI

// 搜索结果结构
struct SearchResult: Identifiable {
    let id: String
    let text: String
    let docType: String
    let source: String
    let title: String
    let score: Double
}

// 搜索脚本输出
struct SearchScriptOutput: Decodable {
    let success: Bool
    let query: String?
    let results: [SearchResultItem]?
    let error: String?
}

struct SearchResultItem: Decodable {
    let id: String
    let text: String
    let doc_type: String
    let source: String
    let title: String
    let score: Double
}

struct KnowledgeBaseListView: View {
    @State private var knowledgeBases: [KnowledgeBase] = []
    @State private var selectedKB: KnowledgeBase?
    @State private var expandedKBs: Set<UUID> = []
    @State private var showingDeleteConfirm = false
    @State private var kbToDelete: KnowledgeBase?
    @State private var errorMessage: String?

    // 搜索相关状态
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchResults: [SearchResult] = []
    @State private var showingSearchPanel = false

    // 文档管理相关状态
    @State private var showingDocManagement = false
    @State private var docManagementKB: KnowledgeBase?

    private let zvecService = ZvecService.shared

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if knowledgeBases.isEmpty {
                emptyStateView
            } else {
                listView
            }
            if showingSearchPanel && selectedKB != nil {
                Divider()
                searchPanelView
            }
            if let error = errorMessage {
                Divider()
                errorView(error)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: loadKnowledgeBases)
        .overlay {
            if showingDocManagement, let kb = docManagementKB {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingDocManagement = false
                        }
                    DocumentManagementView(kb: kb, onDismiss: {
                        showingDocManagement = false
                        loadKnowledgeBases()
                    })
                    .frame(width: 700, height: 500)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                }
            }
        }
    }

    // MARK: - 头部
    private var headerView: some View {
        HStack {
            Text("知识库")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button("刷新") {
                loadKnowledgeBases()
            }
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无知识库")
                .foregroundColor(.secondary)
            Text("在「导入」页面创建知识库并添加文档")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 知识库列表
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(knowledgeBases) { kb in
                    knowledgeBaseCard(kb)
                }
            }
            .padding()
        }
    }

    private func knowledgeBaseCard(_ kb: KnowledgeBase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部行
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundColor(.blue)
                Text(kb.name)
                    .font(.headline)

                Spacer()

                // 展开/折叠按钮
                Button {
                    toggleExpand(kb)
                } label: {
                    Image(systemName: expandedKBs.contains(kb.id) ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // 菜单
                Menu {
                    Button("搜索预览") {
                        selectedKB = kb
                        showingSearchPanel = true
                    }
                    Button("文档管理") {
                        docManagementKB = kb
                        showingDocManagement = true
                    }
                    Divider()
                    Button("删除知识库", role: .destructive) {
                        kbToDelete = kb
                        showingDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }

            Text(kb.displayInfo)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("创建于: \(kb.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            // 文档列表（展开时显示）
            if expandedKBs.contains(kb.id) && !kb.documents.isEmpty {
                Divider()
                documentListView(for: kb)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let kb = kbToDelete {
                    deleteKnowledgeBase(kb)
                }
            }
        } message: {
            if let kb = kbToDelete {
                Text("确定要删除「\(kb.name)」吗？此操作不可撤销。")
            }
        }
    }

    // MARK: - 文档列表
    private func documentListView(for kb: KnowledgeBase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("文档列表")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            ForEach(kb.documents) { doc in
                HStack {
                    Image(systemName: doc.type.icon)
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    Text(doc.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(doc.type.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let pages = doc.pageCount {
                        Text("\(pages)页")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(doc.importedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 搜索面板
    private var searchPanelView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索预览")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    showingSearchPanel = false
                    searchResults.removeAll()
                    searchQuery = ""
                }
            }

            HStack {
                TextField("输入查询词...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { performSearch() }

                Button("搜索") {
                    performSearch()
                }
                .disabled(searchQuery.isEmpty || isSearching)

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(searchResults) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("相似度: \(String(format: "%.2f", result.score))")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                Text(String(result.text.prefix(200)) + (result.text.count > 200 ? "..." : ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
    }

    // MARK: - 错误视图
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .foregroundColor(.red)
            Spacer()
            Button("关闭") {
                errorMessage = nil
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }

    // MARK: - 操作
    private func toggleExpand(_ kb: KnowledgeBase) {
        if expandedKBs.contains(kb.id) {
            expandedKBs.remove(kb.id)
        } else {
            expandedKBs.insert(kb.id)
        }
    }

    private func loadKnowledgeBases() {
        var store = KnowledgeBaseStore.load()
        store.knowledgeBases.removeAll { !FileManager.default.fileExists(atPath: $0.storagePath) }
        store.save()
        knowledgeBases = store.knowledgeBases
    }

    private func deleteKnowledgeBase(_ kb: KnowledgeBase) {
        do {
            try zvecService.deleteCollection(name: kb.name)
            var store = KnowledgeBaseStore.load()
            store.knowledgeBases.removeAll { $0.id == kb.id }
            store.save()
            knowledgeBases = store.knowledgeBases
            if selectedKB?.id == kb.id {
                selectedKB = nil
            }
            expandedKBs.remove(kb.id)
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    private func performSearch() {
        guard let kb = selectedKB, !searchQuery.isEmpty else { return }

        isSearching = true
        searchResults.removeAll()

        Task {
            let config = EmbeddingConfig.load()
            let kbPath = zvecService.kbStoragePath(for: kb.name)

            let nodePath = zvecService.getNodePath()
            let npmGlobalPath = zvecService.getNpmGlobalPath()

            guard let scriptPath = ZvecService.shared.copyScriptToTemp("search.js") else {
                await MainActor.run {
                    errorMessage = "无法获取脚本文件"
                    isSearching = false
                }
                return
            }

            let queryTempFile = FileManager.default.temporaryDirectory.appendingPathComponent("search_query_\(UUID().uuidString).txt")
            do {
                try searchQuery.write(to: queryTempFile, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    errorMessage = "写入查询文件失败"
                    isSearching = false
                }
                return
            }
            defer { try? FileManager.default.removeItem(at: queryTempFile) }

            let shellScriptContent = """
            #!/bin/bash
            NODE_PATH='\(npmGlobalPath)' '\(nodePath)' '\(scriptPath)' \
                --kb-path '\(kbPath.path)' \
                --query-file '\(queryTempFile.path)' \
                --topk 10 \
                --dimension \(kb.vectorDimension) \
                --api-key '\(config.apiKey)' \
                --base-url '\(config.baseURL)' \
                --model '\(config.model)'
            """

            let tempShellScript = FileManager.default.temporaryDirectory.appendingPathComponent("run_search_\(UUID().uuidString).sh")
            do {
                try shellScriptContent.write(to: tempShellScript, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempShellScript.path)
            } catch {
                await MainActor.run {
                    errorMessage = "创建脚本失败"
                    isSearching = false
                }
                return
            }
            defer { try? FileManager.default.removeItem(at: tempShellScript) }

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

                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                        continuation.resume(returning: (output, errorOutput, task.terminationStatus))
                    } catch {
                        continuation.resume(returning: ("", error.localizedDescription, -1))
                    }
                }
            }

            let output = scriptOutput.stdout

            if let outputDataJson = output.data(using: .utf8) {
                let scriptResult = try? JSONDecoder().decode(SearchScriptOutput.self, from: outputDataJson)

                if let results = scriptResult?.results {
                    await MainActor.run {
                        searchResults = results.map { item in
                            SearchResult(
                                id: item.id,
                                text: item.text,
                                docType: item.doc_type,
                                source: item.source,
                                title: item.title,
                                score: item.score
                            )
                        }
                    }
                } else if let error = scriptResult?.error {
                    await MainActor.run {
                        errorMessage = error
                    }
                }
            }

            await MainActor.run {
                isSearching = false
            }
        }
    }
}

// MARK: - 文档管理视图
struct DocumentManagementView: View {
    let kb: KnowledgeBase
    let onDismiss: () -> Void

    @State private var documents: [DocumentRecord] = []
    @State private var selectedDocIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<DocumentRecord>] = [KeyPathComparator(\DocumentRecord.importedAt, order: .reverse)]
    @State private var showingDeleteConfirm = false
    @State private var docToDelete: DocumentRecord?
    @State private var duplicatePairs: [(DocumentRecord, DocumentRecord)] = []
    @State private var showingDuplicateResults = false
    @State private var isDeleting = false
    @State private var isCheckingDuplicates = false

    private var displayedDocuments: [DocumentRecord] {
        var result = documents
        if !searchText.isEmpty {
            let normalizedSearch = normalizeFileName(searchText)
            result = result.filter { normalizeFileName($0.title).contains(normalizedSearch) }
        }
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if documents.isEmpty {
                emptyState
            } else {
                documentTableView
            }
            if let docId = selectedDocIds.first, let doc = documents.first(where: { $0.id == docId }) {
                Divider()
                docDetailView(doc)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: loadDocuments)
        .alert("确认删除", isPresented: $showingDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let doc = docToDelete {
                    deleteDocument(doc)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除「\(docToDelete?.title ?? "")」吗？\n此操作将同时删除 Zvec 中对应的向量数据。")
        }
        .sheet(isPresented: $showingDuplicateResults) {
            duplicateResultsSheet
        }
    }

    private var headerView: some View {
        HStack {
            Text("文档管理: \(kb.name)")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            TextField("搜索文档...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button("检查重复") {
                checkDuplicates()
            }
            .disabled(isCheckingDuplicates || documents.count < 2)
            if isCheckingDuplicates {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Button("关闭") {
                onDismiss()
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无已导入文档")
                .foregroundColor(.secondary)
            Text("如需恢复文档列表，请重新导入文档")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var documentTableView: some View {
        VStack(spacing: 0) {
            Table(displayedDocuments, selection: $selectedDocIds, sortOrder: $sortOrder) {
                TableColumn("文件名", value: \.title) { doc in
                    HStack {
                        Image(systemName: doc.type.icon)
                            .foregroundColor(.blue)
                        Text(doc.title)
                            .lineLimit(1)
                        if isDuplicate(doc) {
                            Text("⚠️")
                                .foregroundColor(.orange)
                        }
                    }
                }
                TableColumn("类型", value: \.type) { doc in
                    Text(doc.type.displayName)
                }
                TableColumn("大小", value: \.fileSize) { doc in
                    Text(doc.fileSizeFormatted)
                }
                TableColumn("块数", value: \.chunkCount) { doc in
                    Text("\(doc.chunkCount)")
                }
                TableColumn("导入时间", value: \.importedAt) { doc in
                    Text(doc.importedAt.formatted())
                }
            }
            .contextMenu {
                if let doc = selectedDoc {
                    Button("删除此文档", role: .destructive) {
                        docToDelete = doc
                        showingDeleteConfirm = true
                    }
                }
            }
        }
    }

    private var selectedDoc: DocumentRecord? {
        guard let id = selectedDocIds.first else { return nil }
        return documents.first { $0.id == id }
    }

    private var duplicateResultsSheet: some View {
        VStack(spacing: 16) {
            Text("发现重复文档")
                .font(.headline)
            if duplicatePairs.isEmpty {
                Text("未发现重复文档")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(duplicatePairs.enumerated()), id: \.offset) { _, pair in
                            HStack {
                                Text(pair.0.title)
                                    .lineLimit(1)
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundColor(.secondary)
                                Text(pair.1.title)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            Button("确定") {
                showingDuplicateResults = false
            }
        }
        .padding()
        .frame(width: 500)
    }

    private func docDetailView(_ doc: DocumentRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文档详情")
                    .font(.headline)
                Spacer()
                Button("删除此文档", role: .destructive) {
                    docToDelete = doc
                    showingDeleteConfirm = true
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "文件名", value: doc.title)
                DetailRow(label: "类型", value: doc.type.displayName)
                DetailRow(label: "大小", value: doc.fileSizeFormatted)
                DetailRow(label: "页数", value: doc.pageCount.map { "\($0)" } ?? "未知")
                DetailRow(label: "块数", value: "\(doc.chunkCount)")
                DetailRow(label: "导入时间", value: doc.importedAt.formatted())
                DetailRow(label: "文件路径", value: doc.sourcePath)
            }

            Spacer()
        }
        .padding()
        .frame(maxHeight: 280)
    }

    private func loadDocuments() {
        documents = kb.documents
    }

    private func isDuplicate(_ doc: DocumentRecord) -> Bool {
        duplicatePairs.contains { $0.0.id == doc.id || $0.1.id == doc.id }
    }

    private func checkDuplicates() {
        isCheckingDuplicates = true
        duplicatePairs.removeAll()

        let normalized = documents.map { doc in
            (doc: doc, normalized: normalizeFileName(doc.title))
        }

        var pairs: [(DocumentRecord, DocumentRecord)] = []
        for i in 0..<normalized.count {
            for j in (i+1)..<normalized.count {
                let n1 = normalized[i].normalized
                let n2 = normalized[j].normalized
                if n1 == n2 || (n1.count >= 10 && n2.count >= 10 && n1.prefix(10) == n2.prefix(10)) {
                    pairs.append((normalized[i].doc, normalized[j].doc))
                }
            }
        }

        duplicatePairs = pairs
        isCheckingDuplicates = false
        showingDuplicateResults = true
    }

    private func deleteDocument(_ doc: DocumentRecord) {
        isDeleting = true

        Task {
            let kbPath = ZvecService.shared.kbStoragePath(for: kb.name).path
            let chunkIds = (0..<doc.chunkCount).map { _ in UUID().uuidString }
            _ = await ZvecService.shared.deleteDocuments(kbPath: kbPath, chunkIds: chunkIds)

            await MainActor.run {
                var store = KnowledgeBaseStore.load()
                if let index = store.knowledgeBases.firstIndex(where: { $0.id == kb.id }) {
                    store.knowledgeBases[index].removeDocument(id: doc.id)
                    store.save()
                    documents.removeAll { $0.id == doc.id }
                    if selectedDocIds.contains(doc.id) {
                        selectedDocIds.remove(doc.id)
                    }
                }
                isDeleting = false
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(3)
            Spacer()
        }
    }
}

#Preview {
    KnowledgeBaseListView()
}

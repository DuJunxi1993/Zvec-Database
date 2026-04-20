# Zvec Database — Agent Development Guide

## Project Overview

macOS native SwiftUI app for managing legal knowledge base. Import documents → chunk → generate vectors → store in Zvec → AI Agent retrieval via MCP.

**Stack**: SwiftUI + Node.js scripts + Zvec vector DB + SiliconFlow API

## Architecture

```
Sources/
├── App/           main.swift, AppDelegate, ContentView, AppState
├── Models/        Document, DocumentChunk, KnowledgeBase, EmbeddingConfig
├── Services/      DocumentParser, ZvecService, EmbeddingService, MCPServerService
└── Views/        DocumentImportView, KnowledgeBaseListView, SettingsView, MCPSettingsView

Resources/scripts/
├── import.js      # Batch insert chunks to Zvec, auto-detect dimension
├── search.js      # Vector similarity search
├── delete.js      # Delete vectors by ID
└── optimize.js    # Optimize Zvec index
```

## Critical Paths

### Document Import Flow
1. User selects files → `handleFileSelection` / `selectFolder`
2. `selectedDocumentType` (Picker) applied to all docs → `doc.userSelectedType`
3. `performImport` → parse documents → `chunkText` with doc type
4. Batches of 5 docs sent to `import.js` → Node.js calls SiliconFlow API → `collection.insertSync`
5. `DocumentRecord` created with `doc.userSelectedType` (NOT `doc.type`)
6. Metadata saved to `~/Library/Application Support/Zvec-Database/knowledgebases.json`

### Storage Paths
- **Zvec collections**: `~/legal_kb/` (ASCII slug path, e.g. `法律库` → `_e6b996e5ba8fe998e5ba8f`)
- **JSON metadata**: `~/Library/Application Support/Zvec-Database/knowledgebases.json`

## Known Issues

### Fixed Bugs
- `chunkByLawArticles` array out-of-bounds (line 147-151): Use `enumerate` instead of `firstIndex` for index lookup
- `import.js` single `insertSync` for large docs: Now batched at 32 chunks per insert

### Document Type Display
- `DocumentRecord.type` must use `doc.userSelectedType` (user-selected), NOT `doc.type` (auto-detected, defaults to `.misc`)
- If existing JSON has wrong types, delete knowledge base and re-import

### Sheet/Window Sizing
- macOS sheets don't respect `.frame(minWidth:height:)` alone
- Current fix: `.overlay` with explicit width/height instead of `.sheet`
- If sheet still shows as tiny rectangle, this is the culprit

## Key Conventions

- **Chinese KB names** → ASCII slug path: `name.data(using: .utf8)!` with hex encoding for non-ASCII bytes
- **Window close (Cmd+W)**: Hides window, doesn't quit app (`isReleasedWhenClosed = false`)
- **Token limit**: 512 tokens per API call → `softLimit = 400` chars, `chunkSize = 400` chars
- **MCP Server launch**: Uses `bash -l -c` (login shell) for environment sourcing

## MCP Server Integration

```bash
uvx zvec-mcp-server
```

App acts as MCP Server host. Clients connect via stdio. Protocol defined by `MCPServerService`.

## SiliconFlow API

- Endpoint: `{baseURL}/embeddings`
- Auth: Bearer token
- Models: Qwen/Qwen3-Embedding-8B, Qwen/Qwen3-Embedding-0.6B, BAAI/bge-large-zh-v1.5, BAAI/bge-m3
- Dimensions: Auto-detected from first batch, stored in `KnowledgeBase.vectorDimension`

## Building

```bash
xcodegen generate
xcodebuild -project Zvec-Database.xcodeproj -scheme Zvec-Database -configuration Release build
```

App location after build:
```
~/Library/Developer/Xcode/DerivedData/Zvec-Database-*/Build/Products/Release/Zvec-Database.app
```

## Zvec NPM Package

The `@zvec/zvec` npm package is called from Node.js scripts, not from Swift. Scripts are bundled in Resources/ and copied to temp at runtime.

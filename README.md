# Zvec Database

阿里Zvec向量知识库 macOS 原生管理应用，基于 SwiftUI 构建，支持向量数据库存储与 AI 检索，针对法律检索进行了分块逻辑增强。
<img width="1000" height="700" alt="iShot_2026-04-20_15 00 30" src="https://github.com/user-attachments/assets/eab03ab8-13ae-4818-ad7b-80f7a88a4226" />
<img width="1000" height="700" alt="iShot_2026-04-20_15 00 47" src="https://github.com/user-attachments/assets/3b465e02-dd0e-42e1-99f0-3cfe5fe04912" />

## 功能

- **文档导入** — 支持 PDF/DOCX/TXT/MD，自动分块
- **智能分块** — 法律/判例/合同按语义边界分块，其他文档按段落分块
- **向量存储** — 对接 SiliconFlow API 生成向量，存入 Zvec 数据库
- **文档管理** — 查看、搜索、删除、重命名文档
- **MCP 服务** — 支持作为 MCP Server 接入 AI Agent

## 环境要求

- macOS 13.0+
- Xcode 15.0+
- Node.js 18+（用于 Zvec 脚本）
- XcodeGen

## 构建

```bash
# 安装依赖
brew install xcodegen node

# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild -project Zvec-Database.xcodeproj -scheme Zvec-Database -configuration Release build
```

## 配置

首次使用需在「设置」页面配置：
- **SiliconFlow API** — API Key 与模型选择
- **向量维度** — 根据模型设置（Qwen3-Embedding 默认 1024）

## 项目结构

```
Sources/
├── App/           # 入口、AppDelegate、ContentView
├── Models/        # 数据模型
├── Services/      # 文档解析、向量服务、MCP 服务
└── Views/         # SwiftUI 视图
Resources/
├── Info.plist
├── AppIcon.icns
└── scripts/       # Node.js 脚本（import/search/delete/optimize）
```

## 许可证

MIT

## 第三方依赖

- [Zvec](https://github.com/alibaba/zvec) — 向量数据库引擎（Apache 2.0）

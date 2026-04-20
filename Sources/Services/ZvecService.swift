import Foundation

class ZvecService {
    static let shared = ZvecService()

    private let fileManager = FileManager.default

    var dataDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let kbDir = home.appendingPathComponent("legal_kb", isDirectory: true)
        try? fileManager.createDirectory(at: kbDir, withIntermediateDirectories: true)
        return kbDir
    }

    func kbStoragePath(for name: String) -> URL {
        let asciiName = name.data(using: .utf8)!.map { byte -> String in
            let c = Character(UnicodeScalar(byte))
            return c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-") ? String(c) : String(format: "_%02x", byte)
        }.joined()
        return dataDirectory.appendingPathComponent(asciiName, isDirectory: true)
    }

    func createCollection(name: String, vectorDimension: Int) throws -> URL {
        let path = kbStoragePath(for: name)
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func listCollections() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents.filter { $0.hasDirectoryPath }.map { $0.lastPathComponent }
    }

    func deleteCollection(name: String) throws {
        let path = kbStoragePath(for: name)
        try fileManager.removeItem(at: path)
    }

    func collectionExists(name: String) -> Bool {
        let path = kbStoragePath(for: name)
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path.path, isDirectory: &isDir) && isDir.boolValue
    }

    func deleteDocuments(kbPath: String, chunkIds: [String]) async -> Bool {
        guard let scriptPath = copyScriptToTemp("delete.js") else {
            return false
        }

        let nodePath = getNodePath()
        let npmGlobalPath = getNpmGlobalPath()

        let idsTempFile = FileManager.default.temporaryDirectory.appendingPathComponent("delete_ids_\(UUID().uuidString).json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: chunkIds),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            try? jsonString.write(to: idsTempFile, atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(at: idsTempFile) }

        let shellScript = """
        #!/bin/bash
        NODE_PATH='\(npmGlobalPath)' '\(nodePath)' '\(scriptPath)' --kb-path '\(kbPath)' --ids-file '\(idsTempFile.path)'
        """

        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("run_delete_\(UUID().uuidString).sh")
        if let e = try? shellScript.write(to: tempScript, atomically: true, encoding: .utf8) { _ = e }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        defer { try? FileManager.default.removeItem(at: tempScript) }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = [tempScript.path]
                let outputPipe = Pipe()
                task.standardOutput = outputPipe
                task.standardError = Pipe()

                do {
                    try task.run()
                    task.waitUntilExit()
                    let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    if let data = output.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool {
                        continuation.resume(returning: success)
                    } else {
                        continuation.resume(returning: task.terminationStatus == 0)
                    }
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

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

        guard let scriptURL = bundleScriptURL else { return nil }
        guard let scriptContent = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let tempScriptURL = tempDir.appendingPathComponent(scriptName)

        do {
            try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptURL.path)
            return tempScriptURL.path
        } catch {
            return nil
        }
    }

    // MARK: - 路径辅助方法

    func getNodePath() -> String {
        let fallbacks = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        for fb in fallbacks {
            if FileManager.default.isExecutableFile(atPath: fb) {
                return fb
            }
        }
        let result = shell("source /etc/profile 2>/dev/null; source ~/.zshrc 2>/dev/null; source ~/.bashrc 2>/dev/null; which node")
        let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return fallbacks[0]
    }

    /// 获取 npm 全局模块路径
    func getNpmGlobalPath() -> String {
        return NSHomeDirectory() + "/.npm-global/lib/node_modules"
    }

    /// 执行 shell 命令并返回输出
    private func shell(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

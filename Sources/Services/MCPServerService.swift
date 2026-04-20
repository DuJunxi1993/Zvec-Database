import Foundation
import Combine

enum ServerStatus: Equatable {
    case unknown
    case stopped
    case starting
    case running
    case error(String)

    var displayText: String {
        switch self {
        case .unknown: return "未知"
        case .stopped: return "已停止"
        case .starting: return "启动中..."
        case .running: return "运行中"
        case .error(let msg): return "错误: \(msg)"
        }
    }

    var color: String {
        switch self {
        case .running: return "green"
        case .stopped, .unknown: return "gray"
        case .starting: return "yellow"
        case .error: return "red"
        }
    }
}

class MCPServerService: ObservableObject {
    static let shared = MCPServerService()

    @Published var status: ServerStatus = .unknown
    @Published var errorMessage: String?

    private var serverProcess: Process?
    private var stdoutHandler: FileHandle?
    private var checkTimer: Timer?
    private let verificationQueue = DispatchQueue(label: "com.zvec.legal.mcp.verification")

    private init() {
        checkStatus()
        startPeriodicCheck()
    }

    deinit {
        checkTimer?.invalidate()
        stopServer()
    }

    func startServer() {
        guard status != .starting else { return }

        status = .starting
        errorMessage = nil

        DispatchQueue.global().async { [weak self] in
            self?.launchServer()
        }
    }

    func stopServer() {
        checkTimer?.invalidate()
        checkTimer = nil

        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil
        stdoutHandler = nil

        DispatchQueue.main.async { [weak self] in
            self?.status = .stopped
        }
    }

    func checkStatus() {
        DispatchQueue.global().async { [weak self] in
            let isRunning = self?.isProcessRunning() ?? false
            DispatchQueue.main.async {
                if isRunning {
                    if self?.status != .running && self?.status != .starting {
                        self?.status = .running
                    }
                } else {
                    if self?.status != .stopped && self?.status != .unknown {
                        self?.status = .stopped
                    }
                }
            }
        }
    }

    private func startPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    private func isProcessRunning() -> Bool {
        if let process = serverProcess, process.isRunning {
            return true
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-l", "-c", "pgrep -f zvec-mcp-server"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func getUvxPath() -> String {
        let fallbacks = ["/opt/homebrew/bin/uvx", "/usr/local/bin/uvx"]
        for fb in fallbacks {
            if FileManager.default.isExecutableFile(atPath: fb) {
                return fb
            }
        }
        return fallbacks[0]
    }

    private func launchServer() {
        let uvxPath = getUvxPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", "'\(uvxPath)' zvec-mcp-server"]

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        process.standardInput = stdinPipe
        process.environment = ProcessInfo.processInfo.environment

        serverProcess = process

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.status = .stopped
                self?.stdoutHandler = nil
            }
        }

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.verifyServer()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = .error("启动失败: \(error.localizedDescription)")
            }
        }
    }

    private func verifyServer() {
        verificationQueue.async { [weak self] in
            guard let self = self else { return }

            guard let process = self.serverProcess, process.isRunning else {
                DispatchQueue.main.async {
                    self.status = .stopped
                }
                return
            }

            DispatchQueue.main.async {
                self.status = .running
            }
        }
    }
}

import Foundation

// MARK: - ShellHelper（Shell 命令执行工具）
// 封装了三种命令执行方式：
// 1. runWithAdmin — 通过 AppleScript 弹出密码框获取管理员权限执行（用于 pmset 等需要 sudo 的命令）
// 2. run — 直接执行普通 shell 命令并返回输出（用于 pmset -g 查询等）
// 3. launchCaffeinate — 启动后台 caffeinate 进程（用于阻止系统睡眠）

struct ShellHelper {

    /// 以管理员权限执行 shell 命令。
    /// 内部通过 AppleScript 的 `do shell script ... with administrator privileges` 实现，
    /// 系统会自动弹出密码输入对话框请求用户授权。
    /// - Parameter command: 要执行的 shell 命令字符串（如 "pmset -a sleep 0"）
    static func runWithAdmin(_ command: String) async throws {
        let script = "do shell script \"\(command)\" with administrator privileges"
        try await runAppleScript(script)
    }

    /// 执行一段 AppleScript 脚本并返回结果。
    /// 使用 NSAppleScript API 在后台线程执行，通过 Swift Concurrency 的
    /// withCheckedThrowingContinuation 桥接为 async/await 调用。
    /// - Parameter source: AppleScript 源代码字符串
    /// - Returns: 脚本执行结果的字符串表示
    @discardableResult
    static func runAppleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let appleScript = NSAppleScript(source: source)
                var errorDict: NSDictionary?
                let result = appleScript?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: ShellError.appleScriptFailed(message))
                } else {
                    continuation.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }

    /// 以普通权限执行 shell 命令并同步返回输出。
    /// 通过 /bin/bash -c 执行，stdout 和 stderr 合并到同一管道。
    /// - Parameter command: 要执行的命令字符串
    /// - Returns: 命令的标准输出（去除首尾空白），出错时返回错误描述
    static func run(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe      // 捕获标准输出
        process.standardError = pipe       // 也捕获标准错误
        do {
            try process.run()
            process.waitUntilExit()        // 同步等待命令执行完成
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// 启动 caffeinate 后台进程，阻止系统因空闲而进入睡眠。
    /// caffeinate 是 macOS 自带工具，-i 标志表示阻止 idle sleep。
    /// 返回 Process 对象，调用方可以通过 terminate() 来终止。
    /// - Returns: 正在运行的 caffeinate Process 实例
    static func launchCaffeinate() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i"]  // -i = prevent idle sleep
        try process.run()
        return process
    }
}

// MARK: - ShellError（Shell 命令错误类型）

/// 自定义错误类型，用于传递 AppleScript 执行失败时的错误信息
enum ShellError: LocalizedError {
    case appleScriptFailed(String)  // AppleScript 执行失败，附带错误详情

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let message):
            return message
        }
    }
}

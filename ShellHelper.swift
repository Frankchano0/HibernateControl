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

    /// 启动 caffeinate 后台进程，全面阻止系统进入任何形式的睡眠。
    /// caffeinate 是 macOS 自带工具，使用多个标志实现全面防护：
    ///   -d 防止显示器睡眠, -i 防止空闲睡眠,
    ///   -m 防止磁盘睡眠, -s 防止系统睡眠, -u 模拟用户活跃
    /// 返回 Process 对象，调用方可以通过 terminate() 来终止。
    /// - Returns: 正在运行的 caffeinate Process 实例
    static func launchCaffeinate() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        let appPID = String(ProcessInfo.processInfo.processIdentifier)
        process.arguments = ["-dimsu", "-w", appPID]  // 仅跟随本 App 生命周期防睡眠
        try process.run()
        return process
    }

    /// 启动 caffeinate（不阻止系统睡眠）。
    /// 使用 -dimu 标志：防止空闲/显示器/磁盘睡眠 + 模拟用户活跃，
    /// 但不持有 PreventSystemSleep assertion，允许电源键/pmset sleepnow 触发睡眠。
    /// 配合 disablesleep=1 使用：disablesleep 阻止合盖睡眠，caffeinate 阻止空闲睡眠，
    /// 而电源键路径畅通。
    static func launchCaffeinateLight() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        let appPID = String(ProcessInfo.processInfo.processIdentifier)
        process.arguments = ["-dimu", "-w", appPID]  // 不含 -s，允许电源键触发系统睡眠
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

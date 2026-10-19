import SwiftUI
import Foundation

// 入口：检测命令行参数决定 GUI 还是 CLI 模式
// 不使用 @main，改为显式 main.swift 控制启动逻辑

let cliArgs = Array(CommandLine.arguments.dropFirst())
    .filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-psn") && $0 != "YES" && $0 != "NO" }

if !cliArgs.isEmpty {
    CLIHandler.run(cliArgs)
    // 不会到达这里（CLIHandler 内部 exit）
} else {
    cduyzhMediaForgeApp.main()
}

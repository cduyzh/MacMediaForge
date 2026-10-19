import SwiftUI
import Photos

// 不使用 @main —— 入口由 main.swift 控制（支持 CLI / GUI 双模式）
struct cduyzhMediaForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    Task { @MainActor in
                        await UpdateChecker.shared.checkForUpdates(isUserInitiated: true)
                    }
                }
                .keyboardShortcut("U", modifiers: .command)
            }
        }
    }
}

// MARK: - AppDelegate（处理 Dock 图标拖拽与窗口唤醒）
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                if window.canBecomeKey {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        // 启动后静默检查更新（延迟 2.5 秒，避免阻塞首屏渲染）
        if AppSettings.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                Task { @MainActor in
                    await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        let videoURLs = urls.filter { videoExts.contains($0.pathExtension.lowercased()) }
        guard !videoURLs.isEmpty else { return }
        NotificationCenter.default.post(name: .addVideosFromDock, object: videoURLs)
    }
}

extension Notification.Name {
    static let addVideosFromDock = Notification.Name("addVideosFromDock")
}

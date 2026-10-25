import SwiftUI
import Photos
import Combine

// 不使用 @main —— 入口由 main.swift 控制（支持 CLI / GUI 双模式）
struct cduyzhMediaForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MediaForge", id: "workspace") {
            ContentView()
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("菜单栏状态") { appDelegate.showMenuBarPanel() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.showWorkspace(destination: "settings") }
                    .keyboardShortcut(",", modifiers: .command)
            }
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

// MARK: - App lifecycle and the persistent workspace
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var statusBar: StatusBarController?
    private weak var workspace: NSWindow?
    private var windowDelegate: WorkspaceWindowDelegate?
    private var pendingDestination: String?
    private var terminationSubscription: AnyCancellable?
    private var waitingForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        statusBar = StatusBarController { [weak self] destination in
            self?.showWorkspace(destination: destination)
        }
        NSApp.activate(ignoringOtherApps: true)

        if AppSettings.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                Task { @MainActor in
                    await UpdateChecker.shared.checkForUpdates(isUserInitiated: false)
                }
            }
        }
    }

    override init() {
        super.init()
        Self.shared = self
    }

    func showMenuBarPanel() { statusBar?.togglePanel() }

    func registerWorkspace(_ window: NSWindow) {
        if workspace === window, window.delegate === windowDelegate { return }
        workspace = window
        window.identifier = NSUserInterfaceItemIdentifier("MediaForgeWorkspace")
        window.isReleasedWhenClosed = false
        let proxy = WorkspaceWindowDelegate(owner: self, original: window.delegate)
        windowDelegate = proxy
        window.delegate = proxy
        if let destination = pendingDestination {
            pendingDestination = nil
            DispatchQueue.main.async { self.showWorkspace(destination: destination) }
        }
    }

    func showWorkspace(destination: String? = nil) {
        guard let window = workspace else { pendingDestination = destination; return }
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        if let destination {
            NotificationCenter.default.post(name: .menuBarNavigate, object: destination)
        }
    }

    func shouldCloseWorkspace(_ window: NSWindow) -> Bool {
        if AppSettings.shared.keepRunningInMenuBar {
            window.orderOut(nil)
        } else {
            // Keep the scene alive until termination is accepted, including if a task is active.
            NSApp.terminate(nil)
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if waitingForTermination { return .terminateLater }
        guard MenuBarState.shared.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "任务尚未完成"
        let isReadingPhotos = MenuBarState.shared.isImporting
        alert.informativeText = isReadingPhotos
            ? "照片图库读取需要等待当前步骤完成后退出。已完成的成果将保留，也可以继续运行。"
            : "退出会停止当前下载或制作。已完成的成果将保留，也可以关闭窗口让任务继续运行。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: isReadingPhotos ? "等待读取完成后退出" : "停止任务并退出")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        waitingForTermination = true
        terminationSubscription = MenuBarState.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.finishTerminationIfIdle()
            }
        NotificationCenter.default.post(name: .cancelActiveWork, object: nil)
        // Work may have finished inside the confirmation alert's nested run loop.
        DispatchQueue.main.async { [weak self] in self?.finishTerminationIfIdle() }
        return .terminateLater
    }

    private func finishTerminationIfIdle() {
        guard waitingForTermination, !MenuBarState.shared.isBusy else { return }
        waitingForTermination = false
        terminationSubscription = nil
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        WorkExecutionManager.shared.cancelAndCleanup()
        statusBar?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspace()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        let videoURLs = urls.filter { videoExts.contains($0.pathExtension.lowercased()) }
        guard !videoURLs.isEmpty else { return }
        showWorkspace(destination: "studio")
        NotificationCenter.default.post(name: .addVideosFromDock, object: videoURLs)
    }
}

/// Preserve SwiftUI's original window delegate for events we do not handle.
@MainActor
private final class WorkspaceWindowDelegate: NSObject, NSWindowDelegate {
    weak var owner: AppDelegate?
    let original: NSWindowDelegate?
    init(owner: AppDelegate, original: NSWindowDelegate?) {
        self.owner = owner
        self.original = original
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { owner?.shouldCloseWorkspace(sender) ?? true }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

extension Notification.Name {
    static let addVideosFromDock = Notification.Name("addVideosFromDock")
    static let cancelActiveWork = Notification.Name("cancelActiveWork")
    static let menuBarNavigate = Notification.Name("menuBarNavigate")
}

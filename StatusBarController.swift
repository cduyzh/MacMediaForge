import AppKit
import SwiftUI
import Combine


@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private enum PanelMode { case status, quickMenu }
    private var mode: PanelMode = .status
    private var statusContent: NSViewController!
    private var quickMenuContent: NSViewController!
    private var subscriptions: Set<AnyCancellable> = []
    private let navigate: (String?) -> Void

    init(navigate: @escaping (String?) -> Void) {
        self.navigate = navigate
        super.init()
        quickMenuContent = NSHostingController(rootView: MenuBarQuickMenu(
            navigate: { [weak self] destination in self?.open(destination) },
            openFolder: { [weak self] in self?.openFolder() },
            quit: { [weak self] in self?.quit() }))
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 455)
        statusContent = NSHostingController(rootView: MenuBarPanel(
            navigate: { [weak self] destination in self?.open(destination) },
            quit: { [weak self] in self?.quit() },
            showMenu: { [weak self] in self?.showContextMenu() }))
        popover.contentViewController = statusContent
        if let button = item.button {
            button.target = self
            button.action = #selector(pressed(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("MediaForge 菜单栏")
        }
        MenuBarState.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    private func refresh() {
        let state = MenuBarState.shared
        item.button?.image = ForgeMenuBarIcon.image(phase: state.current.phase)
        item.button?.title = state.isBusy ? " ·" : ""
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        item.button?.toolTip = "MediaForge · \(state.current.title)\n左键查看状态，右键打开快捷菜单"
        item.button?.setAccessibilityValue(state.current.title)
    }

    @objc private func pressed(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else { togglePanel() }
    }

    func togglePanel() {
        if popover.isShown && mode == .status { popover.performClose(nil) }
        else { present(.status) }
    }

    private func showContextMenu() {
        if popover.isShown && mode == .quickMenu { popover.performClose(nil) }
        else { present(.quickMenu) }
    }

    private func present(_ newMode: PanelMode) {
        guard let button = item.button else { return }
        mode = newMode
        popover.contentViewController = newMode == .status ? statusContent : quickMenuContent
        popover.contentSize = newMode == .status ? NSSize(width: 340, height: 455) : NSSize(width: 280, height: 435)
        // Switching content in one popover also works when the workspace is hidden.
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                self.popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func open(_ destination: String?) { popover.performClose(nil); navigate(destination == "window" ? nil : destination) }
    private func openFolder() { NSWorkspace.shared.open(AppSettings.shared.downloadURL) }
    private func quit() { popover.performClose(nil); NSApp.terminate(nil) }

    func invalidate() { popover.close(); NSStatusBar.system.removeStatusItem(item); subscriptions.removeAll() }
}

private struct MenuBarQuickMenu: View {
    @ObservedObject private var state = MenuBarState.shared
    var navigate: (String?) -> Void
    var openFolder: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(nsImage: ForgeMenuBarIcon.image(phase: state.current.phase))
                    .renderingMode(.template).foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MediaForge").font(.system(size: 13, weight: .semibold))
                    Text(state.current.title).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 9)
            Divider().padding(.vertical, 4)
            MenuBarQuickRow(title: "打开主窗口", icon: "macwindow", shortcut: "⌘O") { navigate(nil) }
                .keyboardShortcut("o", modifiers: .command)
            MenuBarQuickRow(title: "实况制作", icon: "livephoto", shortcut: "⌘1") { navigate("studio") }
                .keyboardShortcut("1", modifiers: .command)
            MenuBarQuickRow(title: "网络提取", icon: "arrow.down.circle", shortcut: "⌘2") { navigate("extractor") }
                .keyboardShortcut("2", modifiers: .command)
            MenuBarQuickRow(title: "历史记录", icon: "clock.arrow.circlepath") { navigate("history") }
            Divider().padding(.vertical, 4)
            MenuBarQuickRow(title: "打开保存目录", icon: "folder", action: openFolder)
            MenuBarQuickRow(title: "设置…", icon: "gearshape", shortcut: "⌘,") { navigate("settings") }
                .keyboardShortcut(",", modifiers: .command)
            Divider().padding(.vertical, 4)
            MenuBarQuickRow(title: "退出 MediaForge", icon: "power", shortcut: "⌘Q", action: quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(10).frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MenuBarQuickRow: View {
    var title: String
    var icon: String
    var shortcut: String = ""
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 12.5))
                Spacer()
                Text(shortcut).font(.system(size: 11)).foregroundStyle(hovering ? .white.opacity(0.8) : Color.secondary)
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(hovering ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

private struct MenuBarPanel: View {
    @ObservedObject private var state = MenuBarState.shared
    @ObservedObject private var settings = AppSettings.shared
    var navigate: (String?) -> Void
    var quit: () -> Void
    var showMenu: () -> Void

    private var tint: Color {
        switch state.current.phase {
        case .working: return .accentColor
        case .success: return .green
        case .attention: return .orange
        case .idle: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(nsImage: ForgeMenuBarIcon.image(phase: .idle))
                    .renderingMode(.template).resizable().frame(width: 25, height: 25)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MediaForge").font(.system(size: 15, weight: .semibold))
                    Text("你的菜单栏媒体工坊").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { navigate(nil) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(ForgeIconButtonStyle()).help("打开主窗口")
                    .accessibilityLabel("打开主窗口")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(state.current.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let progress = state.current.progress {
                        Text("\(Int(progress * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Text(state.current.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(3).frame(height: 44, alignment: .topLeading)
                if let progress = state.current.progress {
                    ProgressView(value: progress).tint(tint)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                shortcut("实况制作", detail: "本地视频转换", icon: "livephoto", destination: "studio")
                shortcut("网络提取", detail: "下载与归档", icon: "arrow.down.circle", destination: "extractor")
            }
            HStack {
                Button { navigate("history") } label: { Label("历史记录", systemImage: "clock.arrow.circlepath") }
                Spacer()
                Button {
                    NSWorkspace.shared.open(settings.downloadURL)
                } label: { Label("保存目录", systemImage: "folder") }
            }
            .buttonStyle(.borderless).font(.system(size: 11.5))
            Divider()
            HStack(spacing: 8) {
                Text(settings.keepRunningInMenuBar ? "关闭窗口后继续运行" : "随主窗口退出")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button(action: showMenu) { Image(systemName: "ellipsis") }
                    .help("快捷菜单").accessibilityLabel("快捷菜单")
                Button { navigate("settings") } label: { Image(systemName: "gearshape") }
                    .help("设置").accessibilityLabel("设置")
                Button(action: quit) { Image(systemName: "power") }
                    .help("退出 MediaForge").accessibilityLabel("退出 MediaForge")
            }
            .buttonStyle(ForgeIconButtonStyle())
        }
        .padding(20).frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shortcut(_ title: String, detail: String, icon: String, destination: String) -> some View {
        Button { navigate(destination) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Capture the actual SwiftUI workspace, without confusing it with a sheet or popover.
struct WorkspaceWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ nsView: WindowProbe, context: Context) { nsView.attachDelegate() }
    final class WindowProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachDelegate()
        }
        func attachDelegate() {
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window, let delegate = AppDelegate.shared else { return }
                delegate.registerWorkspace(window)
            }
        }
    }
}

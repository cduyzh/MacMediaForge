import Foundation
import SwiftUI
import Combine

// MARK: - 实况图转换主业务 ViewModel
@MainActor
class ConversionViewModel: ObservableObject {
    @Published var items: [VideoItem] = [] {
        didSet { observeItems() }
    }
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isCancelling: Bool = false
    @Published var isNetworkRunning = false
    @Published private(set) var lastRunCancelled = false
    @Published private(set) var lastRunFailures = 0
    @Published private(set) var activeTotal = 0
    @Published private(set) var activeCompleted = 0
    @Published var selectedMode: ConversionType = .livePhoto
    private var convertTask: Task<Void, Never>? = nil
    private var itemSubscriptions: [AnyCancellable] = []

    var pendingCount: Int {
        items.filter { item in
            guard item.canConvert else { return false }
            switch item.status {
            case .pending, .failed: return true
            default: return false
            }
        }.count
    }

    private func observeItems() {
        itemSubscriptions = items.map { item in
            item.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    /// 添加视频到转换队列（自动去重）
    func addVideo(url: URL) {
        // 如果列表中已有相同路径的项目，避免重复添加
        if !items.contains(where: { $0.url.path == url.path }) {
            let newItem = VideoItem(url: url)
            items.append(newItem)
        }
    }

    /// 单项和批量共用同一个执行入口，避免重入及模式中途变化。
    func convert(_ item: VideoItem) async {
        guard items.contains(where: { $0.id == item.id }), item.canConvert else { return }
        await run([item])
    }

    /// 只处理等待和失败项目；已完成项目由用户明确重新转换。
    func convertAll() async {
        let pendingItems = items.filter { item in
            guard item.canConvert else { return false }
            switch item.status {
            case .pending, .failed: return true
            default: return false
            }
        }
        await run(pendingItems)
    }

    private func run(_ workItems: [VideoItem]) async {
        guard !isRunning, !isNetworkRunning, !workItems.isEmpty else { return }
        let mode = selectedMode
        lastRunCancelled = false
        lastRunFailures = 0
        activeTotal = workItems.count
        activeCompleted = 0
        isRunning = true
        isCancelling = false

        let task = Task { @MainActor in
            for item in workItems {
                if Task.isCancelled { break }
                await ConversionEngine.processVideo(item, type: mode)
                activeCompleted += 1
            }
        }
        convertTask = task
        await task.value
        lastRunCancelled = task.isCancelled
        lastRunFailures = workItems.filter { if case .failed = $0.status { return true }; return false }.count
        convertTask = nil
        isCancelling = false
        isRunning = false
    }

    /// 等待当前阶段停止并清理后再解锁界面，避免新旧任务交叠。
    func cancelCurrentConversion() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        convertTask?.cancel()
    }

    /// 缓存清除时同步状态
    func handleCacheCleared() {
        items.removeAll { item in
            !FileManager.default.fileExists(atPath: item.url.path)
        }
    }
}

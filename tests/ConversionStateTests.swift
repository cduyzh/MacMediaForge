import Foundation
import SwiftUI

enum ConversionType { case livePhoto, gif, files }
enum ConversionStatus: Equatable {
    case pending, convertingVideo, completed, failed(String)
    var isWorking: Bool { self == .convertingVideo }
}
@MainActor final class VideoItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    @Published var status: ConversionStatus = .pending
    var canConvert = true
    init(url: URL) { self.url = url }
}
@MainActor enum ConversionEngine {
    static var calls: [(String, ConversionType)] = []
    static var release: CheckedContinuation<Void, Never>?
    static var pauses = true
    static var failingFilenames: Set<String> = []
    static func processVideo(_ item: VideoItem, type: ConversionType) async {
        calls.append((item.url.lastPathComponent, type))
        item.status = .convertingVideo
        if pauses { await withCheckedContinuation { release = $0 } }
        if Task.isCancelled { item.status = .pending }
        else if failingFilenames.contains(item.url.lastPathComponent) { item.status = .failed("模拟失败") }
        else { item.status = .completed }
    }
}
@main struct StateChecks {
    @MainActor static func main() async {
        let vm = ConversionViewModel()
        let pending = VideoItem(url: URL(fileURLWithPath: "/tmp/pending.mov"))
        let failed = VideoItem(url: URL(fileURLWithPath: "/tmp/failed.mov"))
        let done = VideoItem(url: URL(fileURLWithPath: "/tmp/done.mov"))
        failed.status = .failed("可重试")
        done.status = .completed
        vm.items = [pending, failed, done]
        precondition(vm.pendingCount == 2)
        let task = Task { await vm.convert(pending) }
        while !vm.isRunning { await Task.yield() }
        while ConversionEngine.release == nil { await Task.yield() }
        vm.cancelCurrentConversion()
        precondition(vm.isRunning && vm.isCancelling)
        await vm.convertAll()
        precondition(ConversionEngine.calls.count == 1, "取消完成前禁止新任务")
        ConversionEngine.release?.resume()
        ConversionEngine.release = nil
        await task.value
        precondition(!vm.isRunning && !vm.isCancelling && pending.status == .pending)
        precondition(vm.activeTotal == 1 && vm.lastRunCancelled, "单项取消必须报告已停止，不能因处理计数达到总数而误报完成")
        precondition(vm.lastRunFailures == 0, "未参与本轮的旧失败不能污染取消结果")

        vm.isNetworkRunning = true
        await vm.convertAll()
        await vm.convert(pending)
        precondition(ConversionEngine.calls.count == 1, "网络任务运行时禁止本地转换")
        vm.isNetworkRunning = false

        ConversionEngine.calls = []
        vm.selectedMode = .files
        let batch = Task { await vm.convertAll() }
        while ConversionEngine.release == nil { await Task.yield() }
        vm.selectedMode = .gif
        ConversionEngine.pauses = false
        ConversionEngine.release?.resume()
        ConversionEngine.release = nil
        await batch.value
        precondition(ConversionEngine.calls.map { $0.0 } == ["pending.mov", "failed.mov"])
        precondition(ConversionEngine.calls.allSatisfy { $0.1 == .files })
        precondition(vm.pendingCount == 0)
        precondition(done.status == .completed)
        await vm.convert(done)
        precondition(ConversionEngine.calls.last?.0 == "done.mov", "单项可明确重转已完成项目")
        precondition(!vm.lastRunCancelled, "后续成功任务必须清除之前的取消结果")

        let untouchedFailure = VideoItem(url: URL(fileURLWithPath: "/tmp/old-failure.mov"))
        let currentFailure = VideoItem(url: URL(fileURLWithPath: "/tmp/current-failure.mov"))
        untouchedFailure.status = .failed("以前的失败")
        vm.items = [untouchedFailure, currentFailure, pending]
        ConversionEngine.failingFilenames = ["current-failure.mov"]
        await vm.convert(currentFailure)
        precondition(vm.lastRunFailures == 1 && !vm.lastRunCancelled, "只统计本轮执行项的失败")
        precondition(untouchedFailure.status == .failed("以前的失败"), "单项制作不应处理其他旧失败")
        await vm.convert(pending)
        precondition(vm.lastRunFailures == 0 && !vm.lastRunCancelled, "成功单项不受队列中其他失败项影响")
        precondition(vm.activeTotal == 1 && vm.activeCompleted == 1)
        precondition(currentFailure.status == .failed("模拟失败"))
        print("PASS: 单项与批量互斥、取消等待、单项取消结果、失败重试、跳过完成项、模式快照、待处理计数、网络任务互斥、本轮失败隔离")
    }
}

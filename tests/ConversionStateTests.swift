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
    static func processVideo(_ item: VideoItem, type: ConversionType) async {
        calls.append((item.url.lastPathComponent, type))
        item.status = .convertingVideo
        if pauses { await withCheckedContinuation { release = $0 } }
        item.status = Task.isCancelled ? .pending : .completed
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
        print("PASS: 单项与批量互斥、取消等待、失败重试、跳过完成项、模式快照、待处理计数、网络任务互斥")
    }
}

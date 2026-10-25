import Foundation
import Combine

/// Window-independent activity, retained while the workspace is hidden.
@MainActor
final class MenuBarState: ObservableObject {
    static let shared = MenuBarState()

    enum Phase: String { case idle, working, success, attention }
    struct Activity: Equatable {
        var title: String
        var detail: String
        var progress: Double?
        var phase: Phase
    }

    @Published private(set) var local: Activity?
    @Published private(set) var network: Activity?
    @Published private(set) var isImporting = false
    @Published private(set) var lastResult: Activity?

    var isBusy: Bool { local != nil || network != nil || isImporting }
    var current: Activity {
        if let network { return network }
        if let local { return local }
        if isImporting { return Activity(title: "正在提取实况视频", detail: "正在读取照片图库中的视频", phase: .working) }
        return lastResult ?? Activity(title: "准备就绪", detail: "从工作区开始下载或制作媒体", phase: .idle)
    }

    func updateLocal(running: Bool, cancelling: Bool, completed: Int, total: Int, detail: String) {
        guard running else { local = nil; return }
        local = Activity(title: cancelling ? "正在停止制作" : "正在制作媒体",
                         detail: detail.isEmpty ? "已处理 \(completed) / \(total) 项" : detail,
                         progress: total > 0 ? Double(completed) / Double(total) : nil, phase: .working)
    }

    func updateNetwork(detail: String, progress: Double) {
        network = Activity(title: "正在提取网络视频", detail: detail,
                           progress: min(1, max(0, progress)), phase: .working)
    }

    func finishNetwork(detail: String, failed: Bool, cancelled: Bool = false) {
        network = nil
        lastResult = Activity(title: cancelled ? "下载已停止" : (failed ? "下载需要关注" : "下载完成"),
                              detail: detail, phase: cancelled ? .idle : (failed ? .attention : .success))
    }

    func finishLocal(failed: Int, cancelled: Bool) {
        local = nil
        lastResult = Activity(title: cancelled ? "制作已停止" : (failed > 0 ? "制作需要关注" : "制作完成"),
                              detail: cancelled ? "已完成的成果仍保留，可回到工作区继续" : (failed > 0 ? "\(failed) 项未完成，请在工作区查看原因" : "前往历史记录或保存目录查看成果"),
                              phase: cancelled ? .idle : (failed > 0 ? .attention : .success))
    }

    func setImporting(_ value: Bool) { isImporting = value }
}

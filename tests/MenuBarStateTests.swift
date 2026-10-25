import Foundation

@main struct MenuBarStateChecks {
    @MainActor static func main() {
        let state = MenuBarState()
        precondition(!state.isBusy && state.current.phase == .idle)
        precondition(state.current.progress == nil)

        state.updateLocal(running: true, cancelling: false, completed: 1, total: 4, detail: "正在转换 video.mov")
        precondition(state.isBusy && state.current.phase == .working)
        precondition(state.current.progress == 0.25 && state.current.detail == "正在转换 video.mov")
        state.updateLocal(running: true, cancelling: true, completed: 1, total: 4, detail: "")
        precondition(state.current.title == "正在停止制作")
        precondition(state.current.detail.contains("1 / 4"))
        state.finishLocal(failed: 0, cancelled: true)
        precondition(!state.isBusy && state.local == nil)
        precondition(state.current.phase == .idle && state.current.title == "制作已停止")

        state.updateLocal(running: true, cancelling: false, completed: 0, total: 0, detail: "")
        precondition(state.current.progress == nil, "未知任务总数应使用不确定进度")
        state.finishLocal(failed: 0, cancelled: false)
        precondition(!state.isBusy && state.current.phase == .success)
        state.updateLocal(running: true, cancelling: false, completed: 1, total: 1, detail: "")
        state.finishLocal(failed: 1, cancelled: false)
        precondition(!state.isBusy && state.current.phase == .attention)
        precondition(state.current.detail.contains("1 项未完成"))

        state.updateNetwork(detail: "开始下载", progress: -0.5)
        precondition(state.isBusy && state.current.phase == .working && state.current.progress == 0)
        state.updateNetwork(detail: "收尾", progress: 1.5)
        precondition(state.current.progress == 1, "网络进度超出范围时应限制在 0...1")
        state.finishNetwork(detail: "已保存 2 个成果", failed: false)
        precondition(!state.isBusy && state.network == nil && state.current.phase == .success)
        precondition(state.current.detail == "已保存 2 个成果")
        state.updateNetwork(detail: "重试下载", progress: 0.5)
        state.finishNetwork(detail: "部分失败", failed: true)
        precondition(!state.isBusy && state.current.phase == .attention)
        state.updateNetwork(detail: "重新下载", progress: 0)
        state.finishNetwork(detail: "保留已完成文件", failed: true, cancelled: true)
        precondition(!state.isBusy && state.current.phase == .idle && state.current.title == "下载已停止")

        state.setImporting(true)
        precondition(state.isBusy && state.current.phase == .working && state.current.progress == nil)
        state.setImporting(false)
        precondition(!state.isBusy && state.current.title == "下载已停止", "导入结束后仍可查看上次处理结果")

        state.updateLocal(running: true, cancelling: false, completed: 0, total: 1, detail: "本地任务")
        state.updateNetwork(detail: "网络任务", progress: 0.5)
        precondition(state.current.detail == "网络任务")
        state.finishNetwork(detail: "网络完成", failed: false)
        precondition(state.isBusy && state.current.detail == "本地任务", "一项工作完成不能隐藏其他仍在运行的工作")
        state.updateLocal(running: false, cancelling: false, completed: 1, total: 1, detail: "")
        precondition(!state.isBusy && state.current.detail == "网络完成")

        print("PASS: 菜单栏空闲、制作进度、停止、成功、失败、进度边界、相册提取、活动优先级与结果保留")
    }
}

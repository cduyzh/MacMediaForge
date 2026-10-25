import Foundation
import AppKit

// MARK: - 全局任务执行与中断清理管理器
public final class WorkExecutionManager: @unchecked Sendable {
    public static let shared = WorkExecutionManager()

    private let lock = NSLock()
    private var activeProcesses: [UUID: Process] = [:]
    private var activeTemporaryFiles: Set<URL> = []

    private init() {}

    /// 注册正在执行的系统进程，返回一个唯一 token 用于注销
    @discardableResult
    public func registerProcess(_ process: Process) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        activeProcesses[id] = process
        return id
    }

    /// 注销已正常结束的进程
    public func unregisterProcess(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        activeProcesses.removeValue(forKey: id)
    }

    /// 注册当前正在生成的临时/半成品文件
    public func registerActiveFile(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        activeTemporaryFiles.insert(url.standardizedFileURL)
    }

    /// 移出已安全完成的文件（保留正常文件）
    public func unregisterActiveFile(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        activeTemporaryFiles.remove(url.standardizedFileURL)
    }

    /// 中断本应用登记的进程，仅清理本轮明确登记的半成品文件。
    @discardableResult
    public func cancelAndCleanup(targetDirectory: URL? = nil) -> Int {
        lock.lock()
        let procs = Array(activeProcesses.values)
        activeProcesses.removeAll()
        let filesToDelete = activeTemporaryFiles
        activeTemporaryFiles.removeAll()
        lock.unlock()

        var cleanedCount = 0

        // 1. 强行终止所有外部子进程
        for proc in procs {
            if proc.isRunning {
                let pid = proc.processIdentifier
                proc.terminate()
                if pid > 0 {
                    // 发送强行终止信号
                    kill(pid, SIGTERM)
                    kill(pid, SIGKILL)
                }
            }
        }

        // 2. 清理所有已记录的正在下载/转码中的半成品文件
        for fileURL in filesToDelete {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    cleanedCount += 1
                } catch {
                    // 忽略单个删除异常
                }
            }
        }

        // 保留 API 参数兼容调用方；文件名、扩展名和零字节都不能证明文件归本轮任务所有。
        // 本地转换使用 defer 清理自己生成的文件，不能在这里扫描和清空共享保存目录。
        _ = targetDirectory

        // 3. 刷新缓存统计
        DispatchQueue.main.async {
            DownloadCacheManager.shared.refreshStats()
        }

        return cleanedCount
    }
}

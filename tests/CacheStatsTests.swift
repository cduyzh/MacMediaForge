import Foundation
import AppKit

@main struct CacheStatsTests {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = root.appendingPathComponent("cduyzhMediaForge")
        let nested = folder.appendingPathComponent("本地/视频")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        UserDefaults.standard.setVolatileDomain([
            "livephotoforge_custom_download_cache_dir": folder.path
        ], forName: UserDefaults.argumentDomain)
        let video = nested.appendingPathComponent("example.mp4")
        let outside = root.appendingPathComponent("personal.mp4")
        try Data(repeating: 1, count: 1024).write(to: video)
        try Data(repeating: 2, count: 4096).write(to: outside)
        try Data(repeating: 3, count: 128).write(to: nested.appendingPathComponent("personal.txt"))
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("alias.mp4"), withDestinationURL: outside)
        let record = DownloadRecord(id: UUID(), sourceURL: "", fileName: video.lastPathComponent, filePath: video.path, fileSize: 1024, createdAt: Date())
        UserDefaults.standard.setVolatileDomain([
            "livephotoforge_custom_download_cache_dir": folder.path,
            "livephotoforge_download_history_records": try JSONEncoder().encode([record])
        ], forName: UserDefaults.argumentDomain)

        let start = Date()
        let manager = DownloadCacheManager(temporaryRoot: root)
        precondition(Date().timeIntervalSince(start) < 1, "初始化不得同步扫描文件目录")
        precondition(manager.isRefreshing)
        // 连续刷新应合并，主线程在扫描期间仍可执行。
        for _ in 0..<20 { manager.refreshStats() }
        let deadline = Date().addingTimeInterval(8)
        while manager.isRefreshing && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(!manager.isRefreshing, "后台统计应正常完成")
        precondition(manager.totalFileCount == 1)
        precondition(manager.totalCacheBytes == 1024)
        precondition(manager.isManagedAppCacheFile(url: video))
        precondition(!manager.isManagedAppCacheFile(url: outside))
        precondition(!manager.isManagedAppCacheFile(url: nested.appendingPathComponent("alias.mp4")))
        precondition(FileManager.default.fileExists(atPath: outside.path), "统计不得修改文件")
        print("PASS: 缓存后台统计、刷新合并、文件去重、非媒体排除、符号链接排除、外部文件保留")
    }
}

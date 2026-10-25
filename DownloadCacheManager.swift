import Foundation
import AppKit

// MARK: - 下载历史记录条目
struct DownloadRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceURL: String
    let fileName: String
    let filePath: String
    var fileSize: Int64
    let createdAt: Date

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: createdAt)
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}

// MARK: - 下载缓存与路径管理器
class DownloadCacheManager: ObservableObject {
    static let shared = DownloadCacheManager()

    private let customDirKey = "livephotoforge_custom_download_cache_dir"
    private let historyRecordsKey = "livephotoforge_download_history_records"
    private let maxHistoryRecords = 500

    @Published var currentCachePath: String = ""
    @Published var isCustomDirectory: Bool = false
    @Published var totalCacheBytes: Int64 = 0
    @Published var totalFileCount: Int = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var statsReadIsSlow = false
    @Published private(set) var lastCleanupFailureCount = 0
    private let statsQueue = DispatchQueue(label: "com.cduyzh.MediaForge.cache-stats", qos: .utility)
    private var statsRevision = UUID()
    private var statsRefreshRequested = false
    private let temporaryRoot: URL
    @Published var historyRecords: [DownloadRecord] = []

    init(temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.temporaryRoot = temporaryRoot
        loadSettings()
        loadHistory()
        refreshStats()
    }

    // MARK: - 目录管理

    /// 默认下载保存专属子目录：系统“下载”目录下的 cduyzhMediaForge 文件夹 (~/Downloads/cduyzhMediaForge)
    var defaultDirectoryURL: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let newURL = downloads.appendingPathComponent("cduyzhMediaForge", isDirectory: true)
        let legacyURL = downloads.appendingPathComponent("LivePhotoForge", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyURL.path) && !FileManager.default.fileExists(atPath: newURL.path) {
            try? FileManager.default.moveItem(at: legacyURL, to: newURL)
        }
        return newURL
    }

    /// 应用专属转换与下载临时目录 (~/tmp/cduyzhMediaForge_Temp)
    var appTempDirectoryURL: URL {
        let temp = temporaryRoot.appendingPathComponent("cduyzhMediaForge_Temp", isDirectory: true)
        ensureDirectoryExists(at: temp)
        return temp
    }

    /// 当前生效的保存目录 URL
    var currentCacheURL: URL {
        if let customPath = UserDefaults.standard.string(forKey: customDirKey),
           !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath, isDirectory: true)
            ensureDirectoryExists(at: url)
            return url
        }
        let def = defaultDirectoryURL
        ensureDirectoryExists(at: def)
        return def
    }

    private func ensureDirectoryExists(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func loadSettings() {
        let custom = UserDefaults.standard.string(forKey: customDirKey)
        if let custom = custom, !custom.isEmpty {
            currentCachePath = custom
            isCustomDirectory = true
        } else {
            currentCachePath = defaultDirectoryURL.path
            isCustomDirectory = false
        }
        ensureDirectoryExists(at: currentCacheURL)
    }

    /// 设置自定义缓存目录
    func setCustomDirectory(url: URL) {
        ensureDirectoryExists(at: url)
        UserDefaults.standard.set(url.path, forKey: customDirKey)
        currentCachePath = url.path
        isCustomDirectory = true
        refreshStats()
    }

    /// 恢复使用默认缓存目录
    func resetToDefaultDirectory() {
        UserDefaults.standard.removeObject(forKey: customDirKey)
        currentCachePath = defaultDirectoryURL.path
        isCustomDirectory = false
        ensureDirectoryExists(at: defaultDirectoryURL)
        refreshStats()
    }

    /// 在访达中打开当前缓存目录
    func openCacheInFinder() {
        let url = currentCacheURL
        ensureDirectoryExists(at: url)
        NSWorkspace.shared.open(url)
    }

    /// 弹出选择文件夹面板更改目录
    func promptChooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.title = "选择视频下载保存文件夹"
        panel.directoryURL = currentCacheURL

        if panel.runModal() == .OK, let selectedURL = panel.url {
            setCustomDirectory(url: selectedURL)
        }
    }

    // MARK: - 安全防护体系 (Safe Guard: 严防误删外部资源)

    /// 系统关键或受保护目录（绝不能删除该目录或递归清空该目录）
    private func isProtectedSystemOrUserDirectory(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        let protectedPaths: Set<String> = [
            "/",
            "/System",
            "/Library",
            "/Applications",
            "/Users",
            "/Volumes",
            "/bin",
            "/sbin",
            "/usr",
            "/private",
            "/var",
            "/tmp",
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Library"
        ]
        return protectedPaths.contains(standardized)
    }

    // 统计使用不可变快照，避免后台扫描读取正在变化的发布属性。
    private struct ManagedFileScope {
        let folder: URL
        let temporaryFolder: URL
        let trackedPaths: Set<String>
        let protectedPaths: Set<String>

        func contains(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.path
            guard !protectedPaths.contains(path), !url.lastPathComponent.hasPrefix(".") else { return false }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return false }
            if trackedPaths.contains(path) { return true }
            let tempPath = temporaryFolder.standardizedFileURL.path
            if path.hasPrefix(tempPath + "/") { return true }
            let name = url.lastPathComponent
            let pattern = #"^(XHSVideo|TwitterVideo|Video)-\d{8}-\d{6}-[A-Za-z0-9]{6}\.mp4$"#
            if name.range(of: pattern, options: .regularExpression) != nil { return true }
            let validExtensions: Set<String> = ["mp4", "mov", "jpg", "jpeg", "gif", "pvt", "md"]
            guard validExtensions.contains(url.pathExtension.lowercased()) else { return false }
            if name.hasPrefix("cduyzhMediaForge-") || name.hasPrefix("LivePhotoForge-") { return true }
            let base = folder.standardizedFileURL.path
            if path.hasPrefix(base + "/"), ["cduyzhMediaForge", "LivePhotoForge"].contains(folder.lastPathComponent) { return true }
            let downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
            return ["cduyzhMediaForge", "LivePhotoForge"].contains { product in
                path.hasPrefix(downloads.appendingPathComponent(product).path + "/")
            }
        }
    }

    private func managedScope() -> ManagedFileScope {
        let home = NSHomeDirectory()
        let protectedPaths = Set(["/", "/System", "/Library", "/Applications", "/Users", "/Volumes", "/bin", "/sbin", "/usr", "/private", "/var", "/tmp", home] + ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Library"].map { home + "/" + $0 })
        return ManagedFileScope(folder: currentCacheURL, temporaryFolder: appTempDirectoryURL, trackedPaths: Set(historyRecords.map { URL(fileURLWithPath: $0.filePath).standardizedFileURL.path }), protectedPaths: protectedPaths)
    }

    /// 校验应用受管的普通文件；符号链接不参与统计与清理。
    func isManagedAppCacheFile(url: URL) -> Bool {
        managedScope().contains(url)
    }

    // MARK: - 历史下载数据管理

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyRecordsKey),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            historyRecords = []
            return
        }
        historyRecords = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(historyRecords) {
            UserDefaults.standard.set(data, forKey: historyRecordsKey)
        }
    }

    /// 为新下载生成目标文件 URL
    func prepareNewDownloadURL(for sourceURL: String) -> URL {
        let folder = currentCacheURL
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let shortId = UUID().uuidString.prefix(6)
        let isXHS = sourceURL.contains("xiaohongshu.com") || sourceURL.contains("xhslink.com") || sourceURL.contains("rednote.com")
        let isTwitter = sourceURL.contains("twitter.com") || sourceURL.contains("x.com")
        let prefix = isXHS ? "XHSVideo" : (isTwitter ? "TwitterVideo" : "Video")
        let filename = "\(prefix)-\(timestamp)-\(shortId).mp4"
        return folder.appendingPathComponent(filename)
    }

    /// 记录完成的下载文件
    /// 同一来源 + 同一文件的重复调用 (下载器与批量编排层都会记录) 只更新大小与时间，不产生重复条目；
    /// 历史记录设有上限，超出时淘汰最旧记录，避免 UserDefaults 无限膨胀。
    func recordCompletedDownload(sourceURL: String, fileURL: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let standardizedPath = fileURL.standardizedFileURL.path
        if let index = historyRecords.firstIndex(where: {
            $0.sourceURL == sourceURL && URL(fileURLWithPath: $0.filePath).standardizedFileURL.path == standardizedPath
        }) {
            historyRecords[index].fileSize = size
            if let encoded = try? JSONEncoder().encode(historyRecords) {
                UserDefaults.standard.set(encoded, forKey: historyRecordsKey)
            }
            refreshStats()
            return
        }
        let record = DownloadRecord(
            id: UUID(),
            sourceURL: sourceURL,
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            fileSize: size,
            createdAt: Date()
        )
        historyRecords.insert(record, at: 0)
        if historyRecords.count > maxHistoryRecords {
            historyRecords.removeLast(historyRecords.count - maxHistoryRecords)
        }
        saveHistory()
        refreshStats()
    }

    /// 删除单条历史记录及对应本地文件（经过严格安全认证）
    func deleteRecord(_ record: DownloadRecord) {
        let fileURL = URL(fileURLWithPath: record.filePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // 安全断言：绝不删除非安全外部文件
            if isManagedAppCacheFile(url: fileURL) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        historyRecords.removeAll { $0.id == record.id }
        saveHistory()
        refreshStats()
    }

    // MARK: - 缓存统计与一键清理 (严格隔离保护)

    private static func enumerateManagedFiles(in folder: URL, scope: ManagedFileScope) -> [URL] {
        var result: [URL] = []
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        let recurse = ["cduyzhMediaForge", "LivePhotoForge", "cduyzhMediaForge_Temp", "LivePhotoForge_Temp"].contains(folder.lastPathComponent)
        if recurse {
            if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in enumerator {
                    if scope.contains(url) { result.append(url) }
                }
            }
        } else if let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            result = contents.filter { scope.contains($0) }
        }
        return result
    }

    private func enumerateManagedFiles(in folder: URL) -> [URL] {
        Self.enumerateManagedFiles(in: folder, scope: managedScope())
    }

    /// 在后台统计文件；读取慢速目录时仍可正常切换页面和操作窗口。
    func refreshStats() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshStats() }
            return
        }
        guard !isRefreshing else {
            statsRefreshRequested = true
            return
        }
        let revision = UUID()
        statsRevision = revision
        isRefreshing = true
        statsReadIsSlow = false
        let scope = managedScope()
        let records = historyRecords
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.statsRevision == revision, self.isRefreshing else { return }
            self.statsReadIsSlow = true
        }
        statsQueue.async { [weak self] in
            let candidates = Self.enumerateManagedFiles(in: scope.folder, scope: scope)
                + records.map { URL(fileURLWithPath: $0.filePath) }
                + Self.enumerateManagedFiles(in: scope.temporaryFolder, scope: scope)
            var seen = Set<String>()
            var size: Int64 = 0
            var count = 0
            for url in candidates where scope.contains(url) {
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted,
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let bytes = values.fileSize else { continue }
                size += Int64(bytes)
                count += 1
            }
            DispatchQueue.main.async {
                guard let self, self.statsRevision == revision else { return }
                self.totalCacheBytes = size
                self.totalFileCount = count
                self.isRefreshing = false
                self.statsReadIsSlow = false
                if self.statsRefreshRequested {
                    self.statsRefreshRequested = false
                    self.refreshStats()
                }
            }
        }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalCacheBytes, countStyle: .file)
    }

    var formattedCacheSize: String {
        formattedTotalSize
    }

    /// 一键清除所有下载缓存数据和文件
    /// 核心保障：绝对只删除通过安全认证的本应用视频缓存与转换碎片，绝不删除其他任何外部或个人资源！
    @discardableResult
    func clearAllCache() -> (freedBytes: Int64, deletedCount: Int) {
        lastCleanupFailureCount = 0
        var freed: Int64 = 0
        var deleted: Int = 0
        var processedPaths = Set<String>()

        // 1. 清理当前保存目录下的受管应用缓存文件
        let folder = currentCacheURL
        let managedFiles = enumerateManagedFiles(in: folder)
        for fileURL in managedFiles {
            let path = fileURL.standardizedFileURL.path
            if !processedPaths.contains(path) {
                processedPaths.insert(path)
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    freed += Int64(fileSize)
                    deleted += 1
                } catch {
                    lastCleanupFailureCount += 1
                }
            }
        }

        // 2. 清理历史下载记录中追踪的文件（无论保存在哪个路径）
        for record in historyRecords {
            let recordURL = URL(fileURLWithPath: record.filePath).standardizedFileURL
            let path = recordURL.path
            if !processedPaths.contains(path) && isManagedAppCacheFile(url: recordURL) {
                processedPaths.insert(path)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                do {
                    try FileManager.default.removeItem(atPath: path)
                    freed += fileSize
                    deleted += 1
                } catch {
                    lastCleanupFailureCount += 1
                }
            }
        }

        // 3. 清理应用专属临时目录中的所有临时碎片
        let tempDir = appTempDirectoryURL
        if let tempContents = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for tmpFile in tempContents {
                let path = tmpFile.standardizedFileURL.path
                if !processedPaths.contains(path) && isManagedAppCacheFile(url: tmpFile) {
                    processedPaths.insert(path)
                    let fileSize = (try? tmpFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    do {
                        try FileManager.default.removeItem(at: tmpFile)
                        freed += Int64(fileSize)
                        deleted += 1
                    } catch {
                        lastCleanupFailureCount += 1
                    }
                }
            }
        }

        // 4. 清空下载历史记录
        historyRecords.removeAll()
        saveHistory()

        // 5. 重新刷新统计
        refreshStats()

        // 6. 发送广播通知
        NotificationCenter.default.post(name: .downloadCacheCleared, object: nil)

        return (freed, deleted)
    }
}

extension Notification.Name {
    static let downloadCacheCleared = Notification.Name("livephotoforge_download_cache_cleared")
}

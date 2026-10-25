import Foundation
import SwiftUI
import AppKit

// MARK: - 操作来源分类
public enum OperationSource: String, Codable, Sendable, CaseIterable {
    case localStudio = "本地制作"
    case networkExtractor = "网络提取"
    case livePhotoExtract = "实况制作"

    public var icon: String {
        switch self {
        case .localStudio: return "film.stack"
        case .networkExtractor: return "arrow.down.circle.dotted"
        case .livePhotoExtract: return "arrow.up.right.video"
        }
    }
}

// MARK: - 操作执行状态
public enum OperationStatus: String, Codable, Sendable, CaseIterable {
    case success = "成功"
    case partialSuccess = "部分成功"
    case failed = "失败"
    case cancelled = "已取消"

    public var color: Color {
        switch self {
        case .success: return .green
        case .partialSuccess: return .orange
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    public var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .partialSuccess: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }
}

// MARK: - 单个产物输出记录
public struct HistoryOutputItem: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public let fileName: String
    public let filePath: String
    public let category: String     // 视频 / 实况 / GIF / 文档
    public let fileSize: Int64

    public var formattedSize: String {
        guard fileSize > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    public init(fileName: String, filePath: String, category: String, fileSize: Int64) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.category = category
        self.fileSize = fileSize
    }
}

// MARK: - 操作历史单条记录模型
public struct OperationHistoryItem: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public let timestamp: Date
    public let source: OperationSource
    public let platform: String       // 小红书 / 推特 / 本地 / 默认
    public let title: String
    public let originalURLOrPath: String?
    public let status: OperationStatus
    public let durationSeconds: Double
    public let outputs: [HistoryOutputItem]
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: OperationSource,
        platform: String,
        title: String,
        originalURLOrPath: String? = nil,
        status: OperationStatus,
        durationSeconds: Double = 0,
        outputs: [HistoryOutputItem] = [],
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.platform = platform
        self.title = title
        self.originalURLOrPath = originalURLOrPath
        self.status = status
        self.durationSeconds = durationSeconds
        self.outputs = outputs
        self.note = note
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    public var timeAgo: String {
        let diff = Date().timeIntervalSince(timestamp)
        if diff < 60 {
            return "刚刚"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins) 分钟前"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours) 小时前"
        } else {
            let days = Int(diff / 86400)
            return "\(days) 天前"
        }
    }
}

// MARK: - 操作历史记录管理器 (单例)
@MainActor
public final class OperationHistoryManager: ObservableObject {
    public static let shared = OperationHistoryManager()

    @Published public private(set) var historyItems: [OperationHistoryItem] = []
    @Published public var filterSource: OperationSource? = nil
    @Published public var filterPlatform: String? = nil
    @Published public var filterStatus: OperationStatus? = nil
    @Published public var searchText: String = ""

    private let fileURL: URL
    private let maxHistoryLimit: Int = 500

    private init() {
        // 存储路径 ~/Library/Application Support/cduyzhMediaForge/operation_history.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("cduyzhMediaForge", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("LivePhotoForge", isDirectory: true)

        if FileManager.default.fileExists(atPath: legacyDir.path) && !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.moveItem(at: legacyDir, to: appDir)
        }

        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        self.fileURL = appDir.appendingPathComponent("operation_history.json")
        loadFromDisk()
    }

    // MARK: - 筛选后的记录
    public var filteredItems: [OperationHistoryItem] {
        historyItems.filter { item in
            if let src = filterSource, item.source != src {
                return false
            }
            if let plat = filterPlatform, item.platform != plat {
                return false
            }
            if let st = filterStatus, item.status != st {
                return false
            }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let term = searchText.lowercased()
                let matchTitle = item.title.lowercased().contains(term)
                let matchURL = item.originalURLOrPath?.lowercased().contains(term) ?? false
                let matchNote = item.note?.lowercased().contains(term) ?? false
                let matchFile = item.outputs.contains { $0.fileName.lowercased().contains(term) }
                return matchTitle || matchURL || matchNote || matchFile
            }
            return true
        }
    }

    // 统计数据
    public var totalCount: Int { historyItems.count }
    public var successCount: Int { historyItems.filter { $0.status == .success }.count }
    public var totalOutputsCount: Int { historyItems.reduce(0) { $0 + $1.outputs.count } }

    // MARK: - 记录添加与操作
    public func record(
        source: OperationSource,
        platform: String,
        title: String,
        originalURLOrPath: String? = nil,
        status: OperationStatus,
        duration: Double = 0,
        outputs: [HistoryOutputItem] = [],
        note: String? = nil
    ) {
        let item = OperationHistoryItem(
            source: source,
            platform: platform,
            title: title,
            originalURLOrPath: originalURLOrPath,
            status: status,
            durationSeconds: duration,
            outputs: outputs,
            note: note
        )
        // 最新记录置顶
        historyItems.insert(item, at: 0)
        if historyItems.count > maxHistoryLimit {
            historyItems = Array(historyItems.prefix(maxHistoryLimit))
        }
        saveToDisk()
    }

    public func removeItem(id: UUID) {
        historyItems.removeAll { $0.id == id }
        saveToDisk()
    }

    public func clearAll() {
        historyItems.removeAll()
        saveToDisk()
    }

    // MARK: - 持久化存储
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(historyItems)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("保存操作历史记录失败: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            self.historyItems = try JSONDecoder().decode([OperationHistoryItem].self, from: data)
        } catch {
            print("读取操作历史记录失败: \(error.localizedDescription)")
        }
    }
}

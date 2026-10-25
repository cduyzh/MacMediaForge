import Foundation

/// 视频清晰度选项枚举
/// 需求约束：支持多个清晰度选择，至少包含 3 个清晰度，1080P 为全系统最大清晰度
public enum VideoQualityOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case p1080 = "1080p"  // 1080P 高清 (系统允许的最大清晰度)
    case p720  = "720p"   // 720P 高清
    case p480  = "480p"   // 480P 标清
    case p360  = "360p"   // 360P 流畅

    public var id: String { rawValue }

    /// 显示名称（用于设置面板与详细菜单）
    public var title: String {
        switch self {
        case .p1080: return "1080P (最大清晰度)"
        case .p720:  return "720P (高清)"
        case .p480:  return "480P (清晰)"
        case .p360:  return "360P (流畅)"
        }
    }

    /// 简短标签（用于卡片徽标或分段选择器）
    public var shortLabel: String {
        switch self {
        case .p1080: return "1080P"
        case .p720:  return "720P"
        case .p480:  return "480P"
        case .p360:  return "360P"
        }
    }

    /// 显示标签（别名）
    public var label: String { shortLabel }

    /// 分辨率最大短边 (横屏时为 height，竖屏时为 width)
    public var maxDimension: Int {
        switch self {
        case .p1080: return 1080
        case .p720:  return 720
        case .p480:  return 480
        case .p360:  return 360
        }
    }

    /// 分辨率最大长边 (16:9 横屏时为 width，9:16 竖屏时为 height)
    public var maxLongDimension: Int {
        switch self {
        case .p1080: return 1920
        case .p720:  return 1280
        case .p480:  return 854
        case .p360:  return 640
        }
    }

    /// Bilibili 对应的最高清晰度 qn ID (上限严格锁定在 116 以内，杜绝 4K/8K)
    public var bilibiliQn: Int {
        switch self {
        case .p1080: return 116 // 1080P 60/高码率/高清
        case .p720:  return 64  // 720P 高清
        case .p480:  return 32  // 480P 清晰
        case .p360:  return 16  // 360P 流畅
        }
    }

    /// 全局默认清晰度（1080P 为系统最大清晰度）
    public static let defaultQuality: VideoQualityOption = .p1080

    /// 全局允许的最大清晰度
    public static let maxAllowedQuality: VideoQualityOption = .p1080

    /// 尝试精确或模糊匹配清晰度，若完全无法识别则返回 nil
    public static func match(_ string: String) -> VideoQualityOption? {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("1080") || clean == "max" || clean == "fhd" || clean == "原画" || clean == "超清" {
            return .p1080
        } else if clean.contains("720") || clean == "hd" || clean == "高清" {
            return .p720
        } else if clean.contains("480") || clean == "sd" || clean == "标清" || clean == "清晰" {
            return .p480
        } else if clean.contains("360") || clean == "ld" || clean == "流畅" {
            return .p360
        }
        // 若超出 1080p（例如 4k, 2k, 8k），根据“1080p是最大清晰度”规则，自动截断限制至 1080p
        if clean.contains("4k") || clean.contains("2160") || clean.contains("2k") || clean.contains("1440") || clean.contains("8k") {
            return .p1080
        }
        return nil
    }

    /// 从字符串智能解析 (支持 "1080p", "1080", "720p", "720", "480p", "480", "360p", "360", "max", "hd" 等，无法识别时兜底默认 1080p)
    public static func from(string: String) -> VideoQualityOption {
        return match(string) ?? .p1080
    }
}

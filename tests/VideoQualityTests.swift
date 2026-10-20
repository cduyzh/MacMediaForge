import Foundation

@main
struct VideoQualityTests {
    static func main() {
        print("=== 正在运行视频清晰度单元与规格测试 ===")

        // 1. 验证清晰度选项数量与档位定义（至少包含 3 个清晰度，1080P 为最大清晰度）
        let allOptions = VideoQualityOption.allCases
        assert(allOptions.count >= 3, "清晰度选项至少需要包含 3 个档位")
        assert(allOptions.count == 4, "预期支持 1080p, 720p, 480p, 360p 共 4 个档位")
        assert(VideoQualityOption.maxAllowedQuality == .p1080, "系统最大允许清晰度必须为 1080P")
        assert(VideoQualityOption.defaultQuality == .p1080, "默认清晰度应为 1080P")

        // 2. 验证各档位的尺寸规格与 B站 QN 映射上限
        let p1080 = VideoQualityOption.p1080
        assert(p1080.maxDimension == 1080, "1080P 短边最大应为 1080")
        assert(p1080.maxLongDimension == 1920, "1080P 长边最大应为 1920")
        assert(p1080.bilibiliQn == 116, "1080P B站 QN 应为 116 (高码率/60帧)，严禁超过 116")
        assert(p1080.bilibiliQn <= 116, "B站最高 QN 必须严格封顶在 116，杜绝 120(4K)/127(8K)")

        let p720 = VideoQualityOption.p720
        assert(p720.maxDimension == 720, "720P 短边最大应为 720")
        assert(p720.maxLongDimension == 1280, "720P 长边最大应为 1280")
        assert(p720.bilibiliQn == 64, "720P B站 QN 应为 64")

        let p480 = VideoQualityOption.p480
        assert(p480.maxDimension == 480, "480P 短边最大应为 480")
        assert(p480.maxLongDimension == 854, "480P 长边最大应为 854")
        assert(p480.bilibiliQn == 32, "480P B站 QN 应为 32")

        let p360 = VideoQualityOption.p360
        assert(p360.maxDimension == 360, "360P 短边最大应为 360")
        assert(p360.maxLongDimension == 640, "360P 长边最大应为 640")
        assert(p360.bilibiliQn == 16, "360P B站 QN 应为 16")

        // 3. 验证字符串解析与模糊匹配
        assert(VideoQualityOption.match("1080p") == .p1080)
        assert(VideoQualityOption.match("1080") == .p1080)
        assert(VideoQualityOption.match("fhd") == .p1080)
        assert(VideoQualityOption.match("原画") == .p1080)
        assert(VideoQualityOption.match("超清") == .p1080)

        assert(VideoQualityOption.match("720p") == .p720)
        assert(VideoQualityOption.match("720") == .p720)
        assert(VideoQualityOption.match("hd") == .p720)
        assert(VideoQualityOption.match("高清") == .p720)

        assert(VideoQualityOption.match("480p") == .p480)
        assert(VideoQualityOption.match("480") == .p480)
        assert(VideoQualityOption.match("sd") == .p480)
        assert(VideoQualityOption.match("标清") == .p480)

        assert(VideoQualityOption.match("360p") == .p360)
        assert(VideoQualityOption.match("360") == .p360)
        assert(VideoQualityOption.match("ld") == .p360)
        assert(VideoQualityOption.match("流畅") == .p360)

        // 4. 关键安全规范校验：当用户或源流传入 4K / 8K / 2K 时，自动封顶限制在 1080P
        assert(VideoQualityOption.match("4K") == .p1080, "4K 必须强制封顶至 1080P")
        assert(VideoQualityOption.match("2160p") == .p1080, "2160P 必须强制封顶至 1080P")
        assert(VideoQualityOption.match("8K") == .p1080, "8K 必须强制封顶至 1080P")
        assert(VideoQualityOption.match("2K") == .p1080, "2K 必须强制封顶至 1080P")
        assert(VideoQualityOption.from(string: "unknown_weird_string") == .p1080, "未知格式默认安全兜底 1080P")

        // 5. 验证 UserDefaults 持久化机制
        let testDefaults = UserDefaults(suiteName: "test.mediaforge.videoquality")!
        testDefaults.removePersistentDomain(forName: "test.mediaforge.videoquality")
        let savedRaw = VideoQualityOption.p720.rawValue
        testDefaults.set(savedRaw, forKey: "lpf_default_video_quality")
        let loadedRaw = testDefaults.string(forKey: "lpf_default_video_quality") ?? ""
        let loadedQuality = VideoQualityOption(rawValue: loadedRaw) ?? .p1080
        assert(loadedQuality == .p720, "UserDefaults 保存并反序列化 720p 成功")

        print("✅ PASS: 所有清晰度档位、1080P封顶限制、尺寸规则与字符串解析测试全部通过！")
    }
}

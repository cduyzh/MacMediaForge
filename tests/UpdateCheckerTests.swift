import Foundation

@main
struct UpdateCheckerTests {
    static func main() async {
        print("▶️ 开始运行 UpdateChecker 单元测试...")

        // 1. 版本号解析测试
        assert(UpdateChecker.parseVersionNumbers("v1.9.0") == [1, 9, 0], "解析 v1.9.0 失败")
        assert(UpdateChecker.parseVersionNumbers("1.10.2") == [1, 10, 2], "解析 1.10.2 失败")
        assert(UpdateChecker.parseVersionNumbers("V2.0.0-rc1") == [2, 0, 0], "解析 V2.0.0-rc1 失败")
        assert(UpdateChecker.parseVersionNumbers("  v3.5  ") == [3, 5], "解析带空格版本失败")
        assert(UpdateChecker.parseVersionNumbers("1.9.0.4") == [1, 9, 0, 4], "解析四段版本号失败")

        // 2. 版本大小比对测试
        assert(UpdateChecker.isRemoteVersion("v1.9.1", newerThan: "1.9.0") == true, "1.9.1 应高于 1.9.0")
        assert(UpdateChecker.isRemoteVersion("v1.10.0", newerThan: "1.9.0") == true, "1.10.0 应高于 1.9.0")
        assert(UpdateChecker.isRemoteVersion("v2.0.0", newerThan: "1.9.0") == true, "2.0.0 应高于 1.9.0")
        assert(UpdateChecker.isRemoteVersion("1.9.0.1", newerThan: "1.9.0") == true, "1.9.0.1 应高于 1.9.0")

        assert(UpdateChecker.isRemoteVersion("1.9.0", newerThan: "1.9.0") == false, "相同版本不应判定为新版本")
        assert(UpdateChecker.isRemoteVersion("v1.9.0", newerThan: "1.9.0") == false, "同版本带v不应判定为新版本")
        assert(UpdateChecker.isRemoteVersion("v1.8.0", newerThan: "1.9.0") == false, "旧版本不应判定为新版本")
        assert(UpdateChecker.isRemoteVersion("v1.0.0", newerThan: "1.9.0") == false, "1.0.0 不应高于 1.9.0")
        assert(UpdateChecker.isRemoteVersion("1.9.0", newerThan: "1.9.0.1") == false, "1.9.0 不应高于 1.9.0.1")

        // 3. 模型解析与辅助属性
        let info = AppReleaseInfo(
            tagName: "v1.9.0",
            name: "cduyzh MediaForge v1.9.0",
            body: "发布更新日志",
            publishedAt: "2026-10-18T10:00:00Z",
            htmlURL: "https://github.com/cduyzh/LivePhotoForge/releases/tag/v1.9.0",
            dmgAssetURL: "https://github.com/cduyzh/LivePhotoForge/releases/download/v1.9.0/cduyzhMediaForge-1.9.0-macos-arm64.dmg",
            zipAssetURL: "https://github.com/cduyzh/LivePhotoForge/releases/download/v1.9.0/cduyzhMediaForge-1.9.0-macos-arm64.zip",
            assetsCount: 2
        )
        assert(info.displayTitle == "cduyzh MediaForge v1.9.0")
        assert(info.cleanVersion == "1.9.0")
        assert(info.dmgAssetURL != nil)

        let infoNoName = AppReleaseInfo(
            tagName: "v2.0.0",
            name: nil,
            body: nil,
            publishedAt: nil,
            htmlURL: "https://github.com/cduyzh/LivePhotoForge/releases/tag/v2.0.0"
        )
        assert(infoNoName.displayTitle == "v2.0.0")
        assert(infoNoName.cleanVersion == "2.0.0")

        // 4. 状态判等
        assert(AppUpdateStatus.idle == AppUpdateStatus.idle)
        assert(AppUpdateStatus.checking == AppUpdateStatus.checking)
        assert(AppUpdateStatus.upToDate(version: "1.9.0") == AppUpdateStatus.upToDate(version: "1.9.0"))
        assert(AppUpdateStatus.upToDate(version: "1.9.0") != AppUpdateStatus.upToDate(version: "1.9.1"))
        assert(AppUpdateStatus.updateAvailable(info) == AppUpdateStatus.updateAvailable(info))

        print("✅ PASS: UpdateChecker 语义版本解析、比较算法、模型与状态转换全部通过！")
    }
}

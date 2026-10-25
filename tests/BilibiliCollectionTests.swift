import Foundation

enum ConversionType: String { case livePhoto, gif, files }

@main
struct BilibiliCollectionTests {
    static func main() async {
        print("▶️ 开始运行 Bilibili 合集解析与选集 Swift 测试...")

        do {
            let url = "https://www.bilibili.com/video/BV18c8Z6XEMS"
            print("  正在调用 BilibiliDownloader.fetchVideoInfo: \(url)")
            let info = try await BilibiliDownloader.fetchVideoInfo(url: url)

            guard info.bvid == "BV18c8Z6XEMS" else {
                fatalError("❌ bvid 不符: \(info.bvid)")
            }
            guard let collection = info.collection else {
                fatalError("❌ 未识别到合集 collection 数据")
            }

            guard collection.type == "ugc_season" else {
                fatalError("❌ 合集类型应为 ugc_season，实际为: \(collection.type)")
            }
            guard collection.epCount >= 200 else {
                fatalError("❌ 合集集数不足 200 集: \(collection.epCount)")
            }
            guard collection.sections.count >= 5 else {
                fatalError("❌ 合集分卷不足 5 个: \(collection.sections.count)")
            }

            let allEps = collection.allEpisodes
            guard allEps.count == collection.epCount else {
                fatalError("❌ allEpisodes 计数 \(allEps.count) 与 epCount \(collection.epCount) 不符")
            }

            guard let firstEp = allEps.first else {
                fatalError("❌ 首个视频为空")
            }
            guard firstEp.bvid.hasPrefix("BV") else {
                fatalError("❌ 首集 BV 号异常: \(firstEp.bvid)")
            }
            guard !firstEp.title.isEmpty else {
                fatalError("❌ 首集标题为空")
            }
            guard !firstEp.durationStr.isEmpty else {
                fatalError("❌ 首集时长格式化为空")
            }

            // 测试当前视频标记
            let currentEp = allEps.first { $0.bvid == "BV18c8Z6XEMS" }
            guard let currentEp = currentEp, currentEp.isCurrent else {
                fatalError("❌ 当前视频 BV18c8Z6XEMS 未被正确识别或 isCurrent 不为 true")
            }

            // 校验 ID 唯一性与分卷关联
            let ids = Set(allEps.map { $0.id })
            guard ids.count == allEps.count else {
                fatalError("❌ 集数 ID 存在重复: 实际 \(ids.count) 项，期望 \(allEps.count) 项")
            }

            print("✅ Bilibili 合集与选集测试全部通过！共校验 \(collection.epCount) 个视频，涵盖 \(collection.sections.count) 个分卷。")
        } catch {
            fatalError("❌ 测试异常失败: \(error.localizedDescription)")
        }
    }
}

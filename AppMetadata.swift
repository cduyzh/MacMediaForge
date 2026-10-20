import Foundation

/// Resolves version metadata from the containing app bundle for GUI and CLI launches.
enum AppMetadata {
    static let bundleIdentifier = "com.cduyzh.MediaForge"

    static func value(forKey key: String) -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return value
        }

        let rawPath = CommandLine.arguments.first ?? ""
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var candidates: [URL] = []
        if rawPath.contains("/") {
            candidates.append(URL(fileURLWithPath: rawPath, relativeTo: currentDirectory))
        } else {
            let searchPaths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
            candidates += searchPaths.map {
                URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(rawPath)
            }
            candidates.append(currentDirectory.appendingPathComponent(rawPath))
        }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let executable = candidate.resolvingSymlinksInPath().standardizedFileURL
            let bundleURL = executable
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            guard let bundle = Bundle(url: bundleURL),
                  bundle.bundleIdentifier == bundleIdentifier,
                  let value = bundle.object(forInfoDictionaryKey: key) as? String else {
                continue
            }
            return value
        }
        return nil
    }

    static var shortVersion: String? { value(forKey: "CFBundleShortVersionString") }
    static var build: String? { value(forKey: "CFBundleVersion") }
}

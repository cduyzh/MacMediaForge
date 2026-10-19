import Foundation
import Photos
import PhotosUI
import SwiftUI

// Extract video from Live Photo
struct LivePhotoExtractor {
    static func extractVideo(from livePhoto: PHLivePhoto) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        if let videoResource = resources.first(where: { $0.type == .pairedVideo }) {
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: videoResource, toFile: tempURL, options: options) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            return tempURL
        }
        throw NSError(domain: "LivePhoto", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video component found"])
    }

    static func extractFromPickerItem(_ item: PhotosPickerItem) async throws -> URL {
        if let livePhoto = try await item.loadTransferable(type: PHLivePhoto.self) {
            return try await extractVideo(from: livePhoto)
        }
        throw NSError(domain: "LivePhoto", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法从所选项中加载实况照片"])
    }
}

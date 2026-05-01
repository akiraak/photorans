import Foundation
import UIKit

enum ImageCompressor {
    /// Anthropic Vision 5MB 上限に対する安全マージン込みの目標サイズ。
    static let defaultTargetBytes: Int = 4_500_000

    /// JPEG データを `targetBytes` 以下になるよう段階的に再エンコードして返す。
    /// 既に target 以下なら無加工で返す。全試行で target を超えた場合は最後 (= 最も小さい)
    /// 試行結果を返す (極端な巨大画像はサーバ側 4xx でユーザに見せる想定)。
    static func compressForUpload(
        jpegData: Data,
        targetBytes: Int = defaultTargetBytes
    ) -> Data {
        if jpegData.count <= targetBytes {
            return jpegData
        }
        guard let image = UIImage(data: jpegData) else {
            return jpegData
        }

        for quality in [0.85, 0.7, 0.5] as [CGFloat] {
            if let data = image.jpegData(compressionQuality: quality),
               data.count <= targetBytes {
                return data
            }
        }

        if let resized = image.resizedToFit(longestEdge: 2048) {
            for quality in [0.85, 0.7, 0.5] as [CGFloat] {
                if let data = resized.jpegData(compressionQuality: quality),
                   data.count <= targetBytes {
                    return data
                }
            }
        }

        if let resized = image.resizedToFit(longestEdge: 1600),
           let data = resized.jpegData(compressionQuality: 0.7) {
            return data
        }

        return image.jpegData(compressionQuality: 0.5) ?? jpegData
    }
}

private extension UIImage {
    func resizedToFit(longestEdge: CGFloat) -> UIImage? {
        let originalLongest = max(size.width, size.height)
        guard originalLongest > longestEdge else { return self }
        let scale = longestEdge / originalLongest
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

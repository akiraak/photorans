import Foundation
import UIKit

enum ImageCompressor {
    /// Anthropic Vision の 5 MiB 上限は **base64 文字列長** に対するもの
    /// (`messages.0.content.0.image.source.base64: image exceeds 5 MB maximum` 検証)。
    /// base64 は raw の 4/3 倍に膨らむので、raw は 3.75 MiB 未満に抑える必要がある。
    /// ここではさらに余裕を持たせて 1.43 MiB ≒ 1_500_000 bytes を target とする
    /// (base64 換算 ~2 MiB)。OCR には十分な情報量。
    static let defaultTargetBytes: Int = 1_500_000

    /// 撮影画像のリサイズ上限長辺。Anthropic Vision は内部で ~1568px に縮小するため、
    /// 2048px もあれば OCR 精度損失はほぼ無い。
    static let defaultMaxLongestEdge: CGFloat = 2048

    /// JPEG データを「Anthropic Vision に投げられる base64 サイズ」 + 「OCR で読める解像度」
    /// の双方を満たすように再エンコードして返す。
    /// - 元画像が `maxLongestEdge` を超えるなら必ず縮小する (フルサイズで通すパスは持たない)
    /// - 縮小後に quality を段階的に下げて `targetBytes` 以下を狙う
    /// - 最終フォールバックとして 1280px / 0.5 を試す
    /// - 全段階で超えた場合は最も小さい結果 (= 最終フォールバック or 縮小後 quality 0.35) を返す
    static func compressForUpload(
        jpegData: Data,
        targetBytes: Int = defaultTargetBytes,
        maxLongestEdge: CGFloat = defaultMaxLongestEdge
    ) -> Data {
        guard let image = UIImage(data: jpegData) else {
            return jpegData
        }

        let resized = image.resizedToFit(longestEdge: maxLongestEdge) ?? image

        for quality in [0.8, 0.65, 0.5] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality),
               data.count <= targetBytes {
                return data
            }
        }

        if let smaller = image.resizedToFit(longestEdge: 1280),
           let data = smaller.jpegData(compressionQuality: 0.5) {
            return data
        }

        return resized.jpegData(compressionQuality: 0.35) ?? jpegData
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

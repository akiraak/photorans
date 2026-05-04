import UIKit

/// 一覧用サムネイルのメモリキャッシュ (`docs/plans/list-thumbnails.md` Step 1)。
///
/// 設計の要点:
/// - `NSCache<NSString, UIImage>` 自体がスレッドセーフなので、外側に追加ロックは置かない。
/// - I/O や縮小処理は持たず、純粋にキー → UIImage の保管のみ。生成は呼び出し側 (`ItemThumbnailView`) に集約。
/// - キーは `<imagePath>@<intW>x<intH>`。同じ画像でも表示サイズが変われば別エントリ扱い (Item 行 56pt と
///   将来の別サイズが衝突しない)。
/// - `countLimit = 200` を上限の目安とする。`NSCache` は超過時に LRU 風に evict する (公式ドキュメントに厳密順序の保証は無いが、
///   メモリ警告で自動 purge される点が UIImage キャッシュ用途には十分)。
/// - キャッシュ無効化 API は意図的に提供しない。Item / Group 削除時に呼ぶ手間より、次回参照で
///   `UIImage(contentsOfFile:)` が nil を返した結果プレースホルダに切り替わる方がシンプル。
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage>

    init(countLimit: Int = 200) {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = countLimit
        self.cache = cache
    }

    func cached(path: String, size: CGSize) -> UIImage? {
        cache.object(forKey: cacheKey(path: path, size: size) as NSString)
    }

    func store(_ image: UIImage, path: String, size: CGSize) {
        cache.setObject(image, forKey: cacheKey(path: path, size: size) as NSString)
    }

    func cacheKey(path: String, size: CGSize) -> String {
        "\(path)@\(Int(size.width))x\(Int(size.height))"
    }
}

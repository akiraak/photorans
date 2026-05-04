import SwiftUI
import UIKit

/// 一覧行用サムネイル View (`docs/plans/list-thumbnails.md` Step 2)。
///
/// - `imagePath` は `Item.imagePath` (Documents 相対パス)。`PhotoStorage.absoluteURL(for:)` で解決する。
/// - 同 path のサムネは `ThumbnailCache.shared` で再利用する。キャッシュヒットなら即同期セット (List スクロールで
///   行が再生成されてもチラつかない)。
/// - 生成は `Task.detached` で off-main に逃がす。`UIImage.preparingThumbnail(of:)` (iOS 15+) は
///   非同期復号 + 縮小を 1 回で済ませる API なので、56pt 表示用にメモリを抑えられる。
/// - VoiceOver: 行ラベルは既に外側で読めるため、サムネ自体は `accessibilityHidden(true)`。
struct ItemThumbnailView: View {
    let imagePath: String
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder
            }
        }
        .accessibilityHidden(true)
        .task(id: imagePath) {
            await loadThumbnail()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: size.width, height: size.height)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private func loadThumbnail() async {
        let path = imagePath
        let targetSize = size

        if let cached = ThumbnailCache.shared.cached(path: path, size: targetSize) {
            image = cached
            return
        }

        let url = PhotoStorage.absoluteURL(for: path)
        let generated = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let raw = UIImage(contentsOfFile: url.path) else { return nil }
            return raw.preparingThumbnail(of: targetSize)
        }.value

        // path が変わった (List 行が別 Item に再利用された) 場合に古い結果を反映しないよう、
        // .task(id:) のキャンセルに任せた上で念のため Task.isCancelled も確認する。
        if Task.isCancelled { return }

        if let generated {
            ThumbnailCache.shared.store(generated, path: path, size: targetSize)
            image = generated
        } else {
            image = nil
        }
    }
}

import SwiftUI

/// `.processing` Item に表示する翻訳中インジケータ (`docs/plans/translation-progress-animation.md` 案 B)。
///
/// 「翻訳中」テキストの右に 3 つのドットを並べ、`scale 0.6 ↔ 1.0` と `opacity 0.3 ↔ 1.0` を
/// 0.2 秒ずつ時差で `repeatForever(autoreverses: true)` させる。チャット系アプリの「相手が入力中」
/// に近い表現で、現行 `ShimmerOverlay` から「光が流れる」モチーフを置き換える。
///
/// VoiceOver には不要なので View 全体を `accessibilityHidden(true)` にする。呼び出し側の
/// `ItemRowView` / `ItemDetailView` で `.accessibilityElement(children: .ignore)` +
/// `.accessibilityLabel("処理中")` を当てて発話を担保する。
struct TranslationProgressIndicator: View {
    enum Style {
        /// 行 (`ItemRowView` `.processing`) — `.body` フォント / 6pt ドット。
        case row
        /// 詳細 (`ItemDetailView` `.processing`) — `.headline` フォント / 8pt ドット。
        case detail
    }

    let style: Style

    var body: some View {
        HStack(spacing: 8) {
            Text("翻訳中")
                .font(textFont)
                .foregroundStyle(.secondary)

            HStack(spacing: dotSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    Dot(size: dotSize, delay: Double(index) * 0.2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var textFont: Font {
        switch style {
        case .row: .body
        case .detail: .headline
        }
    }

    private var dotSize: CGFloat {
        switch style {
        case .row: 6
        case .detail: 8
        }
    }

    private var dotSpacing: CGFloat {
        switch style {
        case .row: 4
        case .detail: 6
        }
    }
}

private struct Dot: View {
    let size: CGFloat
    let delay: Double

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: size, height: size)
            .scaleEffect(animating ? 1.0 : 0.6)
            .opacity(animating ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animating
            )
            .onAppear { animating = true }
    }
}

#Preview("Row") {
    TranslationProgressIndicator(style: .row)
        .padding()
}

#Preview("Detail") {
    TranslationProgressIndicator(style: .detail)
        .padding()
}

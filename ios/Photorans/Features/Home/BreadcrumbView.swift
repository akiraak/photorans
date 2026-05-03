import SwiftUI

/// Group 詳細画面 (グループタブ) の Picker 直下に表示するパンくず。
///
/// 形式: `親 › 子 › [現在地]` (chevron.right で区切り、末尾は Text のみで Button にしない)。
/// 横幅が足りない場合は `ViewThatFits` で **左側 (Root に近い側) を `...` に置き換えた**
/// バリアントへ自動的に切り替わる。
///
/// 関連する純関数 (`ancestorChain` / `popCount`) も同ファイルに置く。1〜2 関数のために
/// ファイル分割すると XcodeGen / pbxproj 再生成のコストに見合わないため統合する。
///
/// ## path と chain の整合前提
///
/// `BreadcrumbView` は `RootView.@State path: NavigationPath` の末尾に積まれた `ItemGroup`
/// 列と、`ancestorChain(of:)` が `parent` を辿って構築する祖先列が **一致** することを前提に
/// `popCount` を計算する。
///
/// 現状は `NavigationLink(value:)` 経由の push しか無く、Item 詳細を開いている間はパンくずを
/// 描画しない画面に居るので両者は一致するが、将来 deep link や `NavigationPath` の永続化を
/// 導入した瞬間にこの前提は崩れる。その時点で `popCount` の引数を path 側 index ベースに
/// 見直すこと (プラン「NavigationStack の path 管理方針 / 前提の限界」参照)。
struct BreadcrumbView: View {
    let chain: [ItemGroup]
    /// 中間階層をタップしたときに呼ばれる。引数は chain 上の index。
    /// 末尾 (現在地) は Button にしないため、ここには **末尾以外の index しか渡らない**。
    let onTap: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(0..<max(chain.count, 1), id: \.self) { dropCount in
                variant(dropCount: dropCount)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `dropCount` 個だけ Root 寄り (chain 先頭側) を `...` に畳んだバリアント。
    /// `dropCount = 0` のときは `...` を出さず chain 全体を描画する。
    /// `dropCount = chain.count - 1` のときは現在地のみで chevron も `...` も出ない。
    @ViewBuilder
    private func variant(dropCount: Int) -> some View {
        HStack(spacing: 6) {
            if dropCount > 0 {
                Text("...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                separator
            }
            ForEach(visibleIndices(dropCount: dropCount), id: \.self) { index in
                let group = chain[index]
                let isLast = (index == chain.count - 1)
                if isLast {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button {
                        onTap(index)
                    } label: {
                        Text(group.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("「\(group.name)」へ移動")
                    separator
                }
            }
        }
    }

    /// `dropCount` 段だけ chain 先頭を畳んだあとに表示すべき index の列。
    private func visibleIndices(dropCount: Int) -> Range<Int> {
        let start = min(dropCount, max(chain.count - 1, 0))
        return start..<chain.count
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

extension BreadcrumbView {
    /// `group` を末尾とする祖先列 `[最上位祖先, ..., 親, group]` を返す。
    ///
    /// `parent` を辿って構築するため、データ整合性が壊れて自己参照ループが発生しても
    /// 64 段で打ち切り無限ループにならないようにする。
    static func ancestorChain(of group: ItemGroup) -> [ItemGroup] {
        var chain: [ItemGroup] = []
        var current: ItemGroup? = group
        var safety = 0
        while let g = current, safety < 64 {
            chain.append(g)
            current = g.parent
            safety += 1
        }
        return chain.reversed()
    }

    /// `chain.count` 段の chain で `tappedIndex` 番目をタップしたとき、
    /// `NavigationPath.removeLast(_:)` に渡すべき pop 段数。
    ///
    /// 例: chain = [GP, P, X] (現在地 X)、P (index=1) タップ → 1 段戻る (= popCount 1)。
    /// 例: chain = [GP, P, X]、GP (index=0) タップ → 2 段戻る (= popCount 2)。
    static func popCount(chainLength: Int, tappedIndex: Int) -> Int {
        chainLength - tappedIndex - 1
    }
}

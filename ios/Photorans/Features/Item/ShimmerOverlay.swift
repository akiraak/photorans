import SwiftUI

/// `.processing` Item の行 / 詳細本文に重ねる、X 軸方向に光が流れるシマー (S6 b / Plan Step 3.6)。
///
/// VoiceOver には不要なので `accessibilityHidden(true)` を付与する。
/// 行 View 側で別途 `.accessibilityLabel("処理中")` を当てて意図を伝える。
struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let gradient = LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .white.opacity(0.0), location: 0.0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .white.opacity(0.0), location: 1.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )

            Rectangle()
                .fill(gradient)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(x: phase * geometry.size.width)
                .blendMode(.plusLighter)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

#Preview {
    Text("翻訳中…")
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(ShimmerOverlay())
        .padding()
}

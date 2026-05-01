import SwiftData
import SwiftUI

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HistoryEntry.createdAt, order: .reverse) private var entries: [HistoryEntry]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "まだ履歴はありません",
                    systemImage: "tray",
                    description: Text("カメラタブで撮影すると、翻訳結果がここに保存されます。")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink {
                            HistoryDetailView(entry: entry)
                        } label: {
                            HistoryRowView(entry: entry)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("履歴")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            let fileURL = PhotoStorage.absoluteURL(for: entry.imagePath)
            try? FileManager.default.removeItem(at: fileURL)
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }
}

private struct HistoryRowView: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.translatedText)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let url = PhotoStorage.absoluteURL(for: entry.imagePath)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.2))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    NavigationStack {
        HistoryListView()
    }
    .modelContainer(for: HistoryEntry.self, inMemory: true)
}

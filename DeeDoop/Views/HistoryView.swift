//
//  HistoryView.swift
//  DeeDoop
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var deletedStore: DeletedItemsStore

    var body: some View {
        List {
            if !deletedStore.mediaItems.isEmpty {
                Section("Photos & Videos deleted by DeeDoop") {
                    ForEach(deletedStore.mediaItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: item.mediaType == "video" ? "video.fill" : "photo.fill")
                                    .foregroundStyle(item.mediaType == "video" ? .purple : .blue)
                                Text(item.filename ?? "Unknown filename")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Self.dateString(item.deletionDate))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if !deletedStore.fileItems.isEmpty {
                Section("Files moved by DeeDoop") {
                    ForEach(deletedStore.fileItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                Text(item.fileName)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Self.dateString(item.deletionDate))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if deletedStore.mediaItems.isEmpty && deletedStore.fileItems.isEmpty {
                Section {
                    Text("No deleted items yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History & Restore")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}


//
//  DeletedItemsStore.swift
//  DeeDoop
//

import Foundation

struct DeletedMediaItem: Identifiable, Codable {
    let id: UUID
    let assetLocalIdentifier: String
    let mediaType: String   // "photo" or "video"
    let fileSize: Int64
    let creationDate: Date?
    let filename: String?
    let deletionDate: Date
}

struct TrashedFileItem: Identifiable, Codable {
    let id: UUID
    let originalPath: String
    let fileName: String
    let fileSize: Int64
    let creationDate: Date?
    let deletionDate: Date
}

final class DeletedItemsStore: ObservableObject {
    static let shared = DeletedItemsStore()

    @Published private(set) var mediaItems: [DeletedMediaItem] = []
    @Published private(set) var fileItems: [TrashedFileItem] = []

    private let storeURL: URL
    private let queue = DispatchQueue(label: "DeletedItemsStore")

    private struct Snapshot: Codable {
        var media: [DeletedMediaItem]
        var files: [TrashedFileItem]
    }

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        storeURL = base.appendingPathComponent("DeletedItems.json")
        load()
    }

    func addMediaItems(_ items: [DeletedMediaItem]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            self.mediaItems.insert(contentsOf: items, at: 0)
            self.save()
        }
    }

    func addFileItems(_ items: [TrashedFileItem]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            self.fileItems.insert(contentsOf: items, at: 0)
            self.save()
        }
    }

    func removeFileItem(id: UUID) {
        DispatchQueue.main.async {
            self.fileItems.removeAll { $0.id == id }
            self.save()
        }
    }

    // MARK: - Persistence

    private func load() {
        queue.async {
            guard let data = try? Data(contentsOf: self.storeURL) else { return }
            guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
            DispatchQueue.main.async {
                self.mediaItems = snapshot.media
                self.fileItems = snapshot.files
            }
        }
    }

    private func save() {
        let snapshot = Snapshot(media: mediaItems, files: fileItems)
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.storeURL, options: .atomic)
            }
        }
    }
}


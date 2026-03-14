//
//  AlbumCreationSession.swift
//  DeeDoop
//

import Foundation

// MARK: - Model

struct AlbumCreationSession: Codable, Identifiable, Hashable {
    var id: UUID
    var albumName: String
    var startDate: Date?
    var endDate: Date?
    var state: State

    // Swipe phase
    var swipePhotoIDs: [String]
    var currentSwipeIndex: Int
    var approvedPhotoIDs: [String]
    var skippedPhotoIDs: [String]
    var toDeletePhotoIDs: [String]

    var createdAlbumIdentifier: String?
    var createdAt: Date

    enum State: String, Codable {
        case naming
        case selectingStartPhoto
        case selectingEndPhoto
        case scanning
        case deduplicating
        case burstFiltering
        case swiping
        case completed
    }

    static func new() -> AlbumCreationSession {
        AlbumCreationSession(
            id: UUID(),
            albumName: "",
            startDate: nil,
            endDate: nil,
            state: .naming,
            swipePhotoIDs: [],
            currentSwipeIndex: 0,
            approvedPhotoIDs: [],
            skippedPhotoIDs: [],
            toDeletePhotoIDs: [],
            createdAlbumIdentifier: nil,
            createdAt: Date()
        )
    }

    var displayName: String { albumName.isEmpty ? "Untitled Album" : albumName }

    var progressSummary: String {
        switch state {
        case .naming: return "Setting up"
        case .selectingStartPhoto: return "Choosing start photo"
        case .selectingEndPhoto: return "Choosing end photo"
        case .scanning: return "Scanning…"
        case .deduplicating: return "Removing duplicates"
        case .burstFiltering: return "Filtering bursts"
        case .swiping:
            let done = currentSwipeIndex
            let total = swipePhotoIDs.count
            return "\(done)/\(total) reviewed"
        case .completed: return "Completed"
        }
    }
}

// MARK: - Store

final class AlbumCreationStore: ObservableObject {
    static let shared = AlbumCreationStore()

    @Published private(set) var sessions: [AlbumCreationSession] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("album_sessions.json")
    }

    private init() { load() }

    func upsert(_ session: AlbumCreationSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        save()
    }

    func delete(_ session: AlbumCreationSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AlbumCreationSession].self, from: data)
        else { return }
        sessions = decoded.filter { !$0.albumName.isEmpty }
        save()
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

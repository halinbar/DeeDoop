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
    var isAlbumMode: Bool

    // Swipe phase
    var swipePhotoIDs: [String]
    var currentSwipeIndex: Int
    var approvedPhotoIDs: [String]
    var skippedPhotoIDs: [String]
    var toDeletePhotoIDs: [String]
    var favoritedPhotoIDs: [String]
    var selectedAlbumIdentifier: String?

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

    // MARK: Coding — isAlbumMode defaults to true for sessions saved before this field existed

    enum CodingKeys: String, CodingKey {
        case id, albumName, startDate, endDate, state, isAlbumMode
        case swipePhotoIDs, currentSwipeIndex
        case approvedPhotoIDs, skippedPhotoIDs, toDeletePhotoIDs, favoritedPhotoIDs
        case selectedAlbumIdentifier
        case createdAlbumIdentifier, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(UUID.self,    forKey: .id)
        albumName             = try c.decode(String.self,  forKey: .albumName)
        startDate             = try c.decodeIfPresent(Date.self,   forKey: .startDate)
        endDate               = try c.decodeIfPresent(Date.self,   forKey: .endDate)
        state                 = try c.decode(State.self,   forKey: .state)
        isAlbumMode           = try c.decodeIfPresent(Bool.self,   forKey: .isAlbumMode) ?? true
        swipePhotoIDs         = try c.decode([String].self, forKey: .swipePhotoIDs)
        currentSwipeIndex     = try c.decode(Int.self,     forKey: .currentSwipeIndex)
        approvedPhotoIDs      = try c.decode([String].self, forKey: .approvedPhotoIDs)
        skippedPhotoIDs       = try c.decode([String].self, forKey: .skippedPhotoIDs)
        toDeletePhotoIDs      = try c.decode([String].self, forKey: .toDeletePhotoIDs)
        favoritedPhotoIDs     = try c.decodeIfPresent([String].self, forKey: .favoritedPhotoIDs) ?? []
        selectedAlbumIdentifier = try c.decodeIfPresent(String.self, forKey: .selectedAlbumIdentifier)
        createdAlbumIdentifier = try c.decodeIfPresent(String.self, forKey: .createdAlbumIdentifier)
        createdAt             = try c.decode(Date.self,    forKey: .createdAt)
    }

    init(id: UUID, albumName: String, startDate: Date?, endDate: Date?,
         state: State, isAlbumMode: Bool,
         swipePhotoIDs: [String], currentSwipeIndex: Int,
         approvedPhotoIDs: [String], skippedPhotoIDs: [String], toDeletePhotoIDs: [String], favoritedPhotoIDs: [String], selectedAlbumIdentifier: String?,
         createdAlbumIdentifier: String?, createdAt: Date) {
        self.id = id
        self.albumName = albumName
        self.startDate = startDate
        self.endDate = endDate
        self.state = state
        self.isAlbumMode = isAlbumMode
        self.swipePhotoIDs = swipePhotoIDs
        self.currentSwipeIndex = currentSwipeIndex
        self.approvedPhotoIDs = approvedPhotoIDs
        self.skippedPhotoIDs = skippedPhotoIDs
        self.toDeletePhotoIDs = toDeletePhotoIDs
        self.favoritedPhotoIDs = favoritedPhotoIDs
        self.selectedAlbumIdentifier = selectedAlbumIdentifier
        self.createdAlbumIdentifier = createdAlbumIdentifier
        self.createdAt = createdAt
    }

    // MARK: Factories

    static func new() -> AlbumCreationSession {
        AlbumCreationSession(
            id: UUID(), albumName: "", startDate: nil, endDate: nil,
            state: .naming, isAlbumMode: true,
            swipePhotoIDs: [], currentSwipeIndex: 0,
            approvedPhotoIDs: [], skippedPhotoIDs: [], toDeletePhotoIDs: [], favoritedPhotoIDs: [], selectedAlbumIdentifier: nil,
            createdAlbumIdentifier: nil, createdAt: Date()
        )
    }

    static func newSort() -> AlbumCreationSession {
        AlbumCreationSession(
            id: UUID(), albumName: "", startDate: nil, endDate: nil,
            state: .naming, isAlbumMode: false,
            swipePhotoIDs: [], currentSwipeIndex: 0,
            approvedPhotoIDs: [], skippedPhotoIDs: [], toDeletePhotoIDs: [], favoritedPhotoIDs: [], selectedAlbumIdentifier: nil,
            createdAlbumIdentifier: nil, createdAt: Date()
        )
    }

    // MARK: Display helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var displayName: String {
        if isAlbumMode {
            return albumName.isEmpty ? "Untitled Album" : albumName
        } else {
            if let s = startDate, let e = endDate {
                return "\(Self.dateFormatter.string(from: s)) – \(Self.dateFormatter.string(from: e))"
            }
            return "New Sort"
        }
    }

    var progressSummary: String {
        switch state {
        case .naming, .selectingStartPhoto, .selectingEndPhoto:
            return "Setting up"
        case .scanning:
            return "Scanning…"
        case .deduplicating:
            return isAlbumMode ? "Removing duplicates" : "Removing duplicates"
        case .burstFiltering:
            return "Filtering bursts"
        case .swiping:
            let done = currentSwipeIndex
            let total = swipePhotoIDs.count
            return "\(done)/\(total) reviewed"
        case .completed:
            return "Completed"
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
        sessions = decoded.filter { session in
            if session.isAlbumMode {
                return !session.albumName.isEmpty
            } else {
                // Sort session: keep only if setup was completed (dates exist)
                return session.startDate != nil && session.endDate != nil
            }
        }
        save()
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

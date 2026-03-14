//
//  AlbumCreationFlowView.swift
//  DeeDoop
//

import Photos
import PhotosUI
import SwiftUI

// MARK: - Entry point (shown from ContentView)

struct AlbumCreationFlowView: View {
    @ObservedObject private var store = AlbumCreationStore.shared
    @State private var activeSession: AlbumCreationSession?

    private var albumSessions: [AlbumCreationSession] {
        store.sessions.filter { $0.isAlbumMode }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)

            if albumSessions.isEmpty && activeSession == nil {
                emptyState
            } else {
                sessionList
            }
        }
        .navigationTitle("Create Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let s = AlbumCreationSession.new()
                    store.upsert(s)
                    activeSession = s
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { activeSession != nil },
            set: { if !$0 {
                if let s = activeSession, s.albumName.isEmpty {
                    store.delete(s)
                }
                activeSession = nil
            }}
        )) {
            if let session = activeSession {
                AlbumSessionCoordinatorView(sessionID: session.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No albums in progress")
                .font(.title2.weight(.semibold))
            Text("Tap + to start building a curated photo album.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                let s = AlbumCreationSession.new()
                store.upsert(s)
                activeSession = s
            } label: {
                Label("Start new album", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private var sessionList: some View {
        List {
            ForEach(albumSessions) { session in
                Button {
                    activeSession = session
                } label: {
                    SessionRowLabel(session: session)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                indexSet.forEach { store.delete(albumSessions[$0]) }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Coordinator

struct AlbumSessionCoordinatorView: View {
    let sessionID: UUID
    @ObservedObject private var store = AlbumCreationStore.shared
    @StateObject private var photoService = PhotoLibraryService()

    private var session: AlbumCreationSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                stepView(for: session)
            } else {
                Text("Session not found")
                    .foregroundStyle(.secondary)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea(edges: .all))
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionID) {
            await ensureAlbumExists()
        }
    }

    /// For sessions created before the "create album at naming time" change, the album
    /// won't exist in Photos yet. This migration creates it once, silently, the first
    /// time such a session is opened.
    @MainActor
    private func ensureAlbumExists() async {
        let setupStates: [AlbumCreationSession.State] = [.naming, .selectingStartPhoto, .selectingEndPhoto]
        guard var s = session,
              s.isAlbumMode,                           // no album for sort sessions
              !setupStates.contains(s.state),          // setup not yet complete
              !s.albumName.isEmpty,
              s.createdAlbumIdentifier == nil           // album not yet created
        else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }

        var placeholderID: String?
        try? await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: s.albumName)
            placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let pid = placeholderID else { return }
        s.createdAlbumIdentifier = pid
        store.upsert(s)
    }

    @ViewBuilder
    private func stepView(for session: AlbumCreationSession) -> some View {
        switch session.state {
        case .naming, .selectingStartPhoto, .selectingEndPhoto:
            AlbumSetupStep(session: session) { updated in
                store.upsert(updated)
            }
        case .scanning:
            AlbumScanningStep(session: session, photoService: photoService) { updated in
                store.upsert(updated)
            }
            .task {
                guard let start = session.startDate, let end = session.endDate else { return }
                await photoService.scanForDuplicates(from: start, to: end, mediaFilter: .photosOnly)
                var s = session
                if !photoService.photoDuplicateGroups.isEmpty {
                    s.state = .deduplicating
                } else if !photoService.photoBurstGroups.isEmpty {
                    s.state = .burstFiltering
                } else {
                    await prepareSwipeIDs(session: &s)
                }
                store.upsert(s)
            }
        case .deduplicating:
            AlbumDedupStep(session: session, photoService: photoService) {
                var s = session
                Task {
                    if !photoService.photoBurstGroups.isEmpty {
                        s.state = .burstFiltering
                    } else {
                        await prepareSwipeIDs(session: &s)
                    }
                    store.upsert(s)
                }
            }
        case .burstFiltering:
            AlbumBurstStep(session: session, photoService: photoService) {
                var s = session
                Task {
                    await prepareSwipeIDs(session: &s)
                    store.upsert(s)
                }
            }
        case .swiping:
            AlbumSwipeStep(session: session) { updated in
                store.upsert(updated)
            }
        case .completed:
            AlbumCompletedView(session: session)
        }
    }

    private func prepareSwipeIDs(session: inout AlbumCreationSession) async {
        guard let start = session.startDate, let end = session.endDate else { return }
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            start as NSDate, end as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var ids: [String] = []
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        session.swipePhotoIDs = ids
        session.currentSwipeIndex = 0
        session.state = .swiping
    }
}

// MARK: - Step: Combined setup (name + first/last photo)

private struct AlbumSetupStep: View {
    let session: AlbumCreationSession
    let onNext: (AlbumCreationSession) -> Void

    @State private var name: String = ""
    @State private var startDate: Date?
    @State private var startThumb: UIImage?
    @State private var endDate: Date?
    @State private var endThumb: UIImage?
    @State private var isWorking = false
    @State private var pickerTarget: PickerTarget?
    @FocusState private var isNameFocused: Bool

    private enum PickerTarget: String, Identifiable {
        case start, end
        var id: String { rawValue }
    }

    private var isAlbumMode: Bool { session.isAlbumMode }

    private var canContinue: Bool {
        let nameOK = !isAlbumMode || !name.trimmingCharacters(in: .whitespaces).isEmpty
        return nameOK && startDate != nil && endDate != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Album name — only shown in album mode
                if isAlbumMode {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Album name", systemImage: "photo.stack")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Summer 2024", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .disabled(isWorking)
                    }
                }

                // Photo range — in album mode, locked until the album has a name
                let hasName = !isAlbumMode || !name.trimmingCharacters(in: .whitespaces).isEmpty
                VStack(alignment: .leading, spacing: 10) {
                    Label("Photo range", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        photoPickerCard(
                            label: "First photo",
                            icon: "arrow.up.left.circle",
                            thumb: startThumb,
                            date: startDate
                        ) { pickerTarget = .start }

                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .frame(width: 24)

                        photoPickerCard(
                            label: "Last photo",
                            icon: "arrow.down.right.circle",
                            thumb: endThumb,
                            date: endDate
                        ) { pickerTarget = .end }
                    }
                    .disabled(!hasName)
                    .opacity(hasName ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.2), value: hasName)
                }

                // Continue button
                if isWorking {
                    ProgressView(isAlbumMode ? "Creating album…" : "Setting up…").tint(.orange)
                } else {
                    Button { Task { await advance() } } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canContinue ? Color.orange : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canContinue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .navigationTitle(isAlbumMode ? "New Album" : "Sort Photos")
        .onAppear { populate() }
        .sheet(item: $pickerTarget) { target in
            SinglePhotoPickerView { id, date in
                pickerTarget = nil
                switch target {
                case .start:
                    startDate = date
                    Task { startThumb = await loadThumbnail(for: id) }
                case .end:
                    endDate = date
                    Task { endThumb = await loadThumbnail(for: id) }
                }
            } onCancel: {
                pickerTarget = nil
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func photoPickerCard(
        label: String,
        icon: String,
        thumb: UIImage?,
        date: Date?,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    date != nil ? Color.orange.opacity(0.5) : Color.gray.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.5, dash: date == nil ? [6, 3] : [])
                                )
                        )
                        .aspectRatio(3 / 4, contentMode: .fit)

                    if let thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .aspectRatio(3 / 4, contentMode: .fit)
                    } else {
                        Image(systemName: icon)
                            .font(.largeTitle)
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if let date {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Tap to pick")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func populate() {
        name = session.albumName
        startDate = session.startDate
        endDate = session.endDate
        // Pre-load thumbnails if dates came from a resumed session
        isNameFocused = name.isEmpty
    }

    private func loadThumbnail(for identifier: String) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.isNetworkAccessAllowed = false
        var didResume = false
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 240, height: 320),
                contentMode: .aspectFill,
                options: opts
            ) { image, _ in
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: image)
            }
        }
    }

    @MainActor
    private func advance() async {
        guard let s1 = startDate, let e1 = endDate else { return }
        if isAlbumMode {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        }
        isWorking = true

        var s = session
        s.startDate = min(s1, e1)
        s.endDate   = max(s1, e1)

        if isAlbumMode {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            s.albumName = trimmed
            // Create the album in Photos so it appears in the gallery immediately.
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if status == .authorized || status == .limited {
                var placeholderID: String?
                try? await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCollectionChangeRequest
                        .creationRequestForAssetCollection(withTitle: trimmed)
                    placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
                }
                s.createdAlbumIdentifier = placeholderID
            }
        }

        s.state = .scanning
        isWorking = false
        onNext(s)
    }
}

// MARK: - Step: Scanning

struct AlbumScanningStep: View {
    let session: AlbumCreationSession
    @ObservedObject var photoService: PhotoLibraryService
    let onComplete: (AlbumCreationSession) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView(value: photoService.scanProgress)
                .progressViewStyle(.linear)
                .tint(.orange)
                .padding(.horizontal, 40)
            Text("Scanning photos…")
                .font(.headline)
            Text("Finding duplicates and bursts in your date range.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .navigationTitle(session.displayName)
    }
}

// MARK: - Step: Dedup

struct AlbumDedupStep: View {
    let session: AlbumCreationSession
    @ObservedObject var photoService: PhotoLibraryService
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if photoService.photoDuplicateGroups.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("All duplicates resolved")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }
            } else {
                DuplicateGroupsListView(photoService: photoService)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("Remove Duplicates")
    }
}

// MARK: - Step: Burst filtering

struct AlbumBurstStep: View {
    let session: AlbumCreationSession
    @ObservedObject var photoService: PhotoLibraryService
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if photoService.photoBurstGroups.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("All bursts resolved")
                        .font(.title2.weight(.semibold))
                    Spacer()
                }
            } else {
                List {
                    Section {
                        Text("\(photoService.photoBurstGroups.count) burst group(s) found. Tap each to keep your favorites.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(photoService.photoBurstGroups) { group in
                        NavigationLink {
                            BurstGroupDetailView(group: group, photoService: photoService)
                        } label: {
                            DuplicateGroupRow(group: group)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }

            Button(action: onContinue) {
                Text("Continue to Review")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("Filter Bursts")
    }
}

// MARK: - Step: Tinder-style swipe

struct AlbumSwipeStep: View {
    let session: AlbumCreationSession
    let onUpdate: (AlbumCreationSession) -> Void

    @State private var localSession: AlbumCreationSession
    @State private var currentAsset: PHAsset?
    @State private var burstSiblings: [PHAsset] = []
    @State private var showFinishConfirmation = false
    @State private var isCreatingAlbum = false
    @State private var albumError: String?
    /// Tracks IDs already successfully added to the Photos album this session,
    /// so finalizeAlbum() doesn't create duplicates.
    @State private var addedToAlbumIDs: Set<String> = []
    @State private var showSkippedReview = false

    init(session: AlbumCreationSession, onUpdate: @escaping (AlbumCreationSession) -> Void) {
        self.session = session
        self.onUpdate = onUpdate
        self._localSession = State(initialValue: session)
    }

    private var remaining: Int {
        max(localSession.swipePhotoIDs.count - localSession.currentSwipeIndex, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar + counters
            VStack(spacing: 6) {
                ProgressView(
                    value: Double(localSession.currentSwipeIndex),
                    total: Double(max(localSession.swipePhotoIDs.count, 1))
                )
                .tint(.orange)
                .padding(.horizontal)

                HStack {
                    Label("\(localSession.approvedPhotoIDs.count)", systemImage: "heart.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    VStack(spacing: 1) {
                        Text("\(localSession.currentSwipeIndex + 1) / \(localSession.swipePhotoIDs.count)")
                            .foregroundStyle(.primary)
                        Text("\(remaining) left")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                    }
                    Spacer()
                    Label("\(localSession.toDeletePhotoIDs.count)", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            if remaining == 0 {
                // All done — offer to create the album
                doneView
            } else                 if let asset = currentAsset {
                SwipeCardView(
                    asset: asset,
                    burstSiblings: burstSiblings,
                    existingDecision: currentDecision,
                    isAlbumMode: localSession.isAlbumMode
                ) { action in
                    recordSwipe(action: action)
                }
                // Force a new view instance (fresh @State) whenever the card changes.
                .id(asset.localIdentifier)
                .padding(.horizontal, 12)

                // Edit toolbar — rotate / crop
                PhotoEditBar(asset: asset) { loadCurrent() }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }

            // Film strip — always visible so the user can see context and tap to navigate
            if !localSession.swipePhotoIDs.isEmpty {
                SwipeFilmStrip(
                    swipePhotoIDs: localSession.swipePhotoIDs,
                    currentIndex: localSession.currentSwipeIndex,
                    approvedIDs: Set(localSession.approvedPhotoIDs),
                    skippedIDs: Set(localSession.skippedPhotoIDs),
                    toDeleteIDs: Set(localSession.toDeletePhotoIDs),
                    burstSiblingIDs: Set(burstSiblings.map(\.localIdentifier)),
                    onNavigate: navigate(to:)
                )
            }

            // Metadata for the current photo
            if let asset = currentAsset {
                PhotoMetadataBar(asset: asset)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Spacer(minLength: 4)
        }
        .navigationTitle(localSession.displayName)
        .navigationDestination(isPresented: $showSkippedReview) {
            SkippedPhotosReviewView(
                reviewIDs: skippedAndUntaggedIDs,
                isAlbumMode: localSession.isAlbumMode,
                onDecision: { id, action in applyDecision(id: id, action: action) }
            )
        }
        .onAppear { loadCurrent() }
        .alert(localSession.isAlbumMode ? "Album creation failed" : "Finalisation failed",
               isPresented: .constant(albumError != nil)) {
            Button("OK") { albumError = nil }
        } message: {
            Text(albumError ?? "")
        }
    }

    private var skippedAndUntaggedIDs: [String] {
        let decided = Set(localSession.approvedPhotoIDs + localSession.toDeletePhotoIDs)
        return localSession.swipePhotoIDs.filter { !decided.contains($0) }
    }

    private var doneView: some View {
        let isAlbum = localSession.isAlbumMode
        return VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("All photos reviewed!")
                .font(.title2.weight(.semibold))
            VStack(spacing: 8) {
                summaryRow(icon: "heart.fill", color: .green,
                           text: "\(localSession.approvedPhotoIDs.count) \(isAlbum ? "added to album" : "kept")")
                summaryRow(icon: "arrow.down.circle.fill", color: .blue,
                           text: "\(localSession.skippedPhotoIDs.count) \(isAlbum ? "kept but not in album" : "skipped")")
                summaryRow(icon: "trash.fill", color: .red,
                           text: "\(localSession.toDeletePhotoIDs.count) will be deleted")
            }

            VStack(spacing: 12) {
                if !skippedAndUntaggedIDs.isEmpty {
                    Button { showSkippedReview = true } label: {
                        Label("Review skipped & untagged (\(skippedAndUntaggedIDs.count))",
                              systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                }

                if isCreatingAlbum {
                    ProgressView(isAlbum ? "Creating album…" : "Finishing…")
                        .tint(.orange)
                } else {
                    Button {
                        Task { await finalizeAlbum() }
                    } label: {
                        Label(
                            isAlbum
                                ? "Create \"\(localSession.albumName)\" album"
                                : "Finish sorting",
                            systemImage: isAlbum ? "plus.rectangle.on.folder" : "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline)
        }
    }

    private func recordSwipe(action: AlbumSwipeAction) {
        guard localSession.currentSwipeIndex < localSession.swipePhotoIDs.count else { return }
        let id = localSession.swipePhotoIDs[localSession.currentSwipeIndex]

        // If the photo was previously approved and is in the album, but we're now changing
        // the decision, remove it from the album immediately.
        if action != .approve && addedToAlbumIDs.contains(id) {
            addedToAlbumIDs.remove(id)
            Task { await removePhotoFromAlbum(id: id) }
        }

        // Replace any existing decision.
        localSession.approvedPhotoIDs.removeAll { $0 == id }
        localSession.toDeletePhotoIDs.removeAll { $0 == id }
        localSession.skippedPhotoIDs.removeAll { $0 == id }
        switch action {
        case .approve:
            localSession.approvedPhotoIDs.append(id)
            // Add to the album right away (only if not already there).
            if !addedToAlbumIDs.contains(id) {
                addedToAlbumIDs.insert(id)
                Task { await addPhotoToAlbum(id: id) }
            }
        case .delete: localSession.toDeletePhotoIDs.append(id)
        case .skip:   localSession.skippedPhotoIDs.append(id)
        }
        localSession.currentSwipeIndex += 1
        onUpdate(localSession)
        loadCurrent()
    }

    /// Applies a tagging decision for an arbitrary photo ID without advancing the swipe index.
    /// Used by the skipped/untagged review so the user can re-tag before finalising.
    private func applyDecision(id: String, action: AlbumSwipeAction) {
        if action != .approve && addedToAlbumIDs.contains(id) {
            addedToAlbumIDs.remove(id)
            Task { await removePhotoFromAlbum(id: id) }
        }
        localSession.approvedPhotoIDs.removeAll { $0 == id }
        localSession.toDeletePhotoIDs.removeAll { $0 == id }
        localSession.skippedPhotoIDs.removeAll { $0 == id }
        switch action {
        case .approve:
            localSession.approvedPhotoIDs.append(id)
            if !addedToAlbumIDs.contains(id) {
                addedToAlbumIDs.insert(id)
                Task { await addPhotoToAlbum(id: id) }
            }
        case .delete: localSession.toDeletePhotoIDs.append(id)
        case .skip:   localSession.skippedPhotoIDs.append(id)
        }
        onUpdate(localSession)
    }

    /// Adds a photo to the album that was created at naming time.
    private func addPhotoToAlbum(id: String) async {
        guard let albumID = localSession.createdAlbumIdentifier else { return }
        let albumFetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID], options: nil)
        guard let album = albumFetch.firstObject else { return }
        let assetFetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assetFetch.firstObject else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        }
    }

    /// Removes a photo from the album (called when the user re-swipes away from approve).
    private func removePhotoFromAlbum(id: String) async {
        guard let albumID = localSession.createdAlbumIdentifier else { return }
        let albumFetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID], options: nil)
        guard let album = albumFetch.firstObject else { return }
        let assetFetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assetFetch.firstObject else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.removeAssets([asset] as NSArray)
        }
    }

    /// Returns the existing decision for the photo currently on screen, if any.
    private var currentDecision: AlbumSwipeAction? {
        guard localSession.currentSwipeIndex < localSession.swipePhotoIDs.count else { return nil }
        let id = localSession.swipePhotoIDs[localSession.currentSwipeIndex]
        if localSession.approvedPhotoIDs.contains(id) { return .approve }
        if localSession.toDeletePhotoIDs.contains(id) { return .delete }
        if localSession.skippedPhotoIDs.contains(id)  { return .skip }
        return nil
    }

    private func loadCurrent() {
        // Skip IDs that no longer exist in library.
        while localSession.currentSwipeIndex < localSession.swipePhotoIDs.count {
            let id = localSession.swipePhotoIDs[localSession.currentSwipeIndex]
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            if let asset = result.firstObject {
                currentAsset = asset
                loadBurstSiblings(for: asset)
                return
            }
            localSession.currentSwipeIndex += 1
        }
        currentAsset = nil
        burstSiblings = []
    }

    private func loadBurstSiblings(for asset: PHAsset) {
        guard let date = asset.creationDate else { burstSiblings = []; return }
        let threshold: TimeInterval = 3
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND localIdentifier != %@",
            date.addingTimeInterval(-threshold) as NSDate,
            date.addingTimeInterval(threshold) as NSDate,
            asset.localIdentifier
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var siblings: [PHAsset] = []
        result.enumerateObjects { a, _, _ in siblings.append(a) }
        burstSiblings = siblings
    }

    /// Jump to any photo in the roll. Keeps its existing decision visible on the card;
    /// the user can swipe to override it, or just move on.
    private func navigate(to targetIndex: Int) {
        guard targetIndex >= 0,
              targetIndex < localSession.swipePhotoIDs.count,
              targetIndex != localSession.currentSwipeIndex else { return }
        localSession.currentSwipeIndex = targetIndex
        onUpdate(localSession)
        loadCurrent()
    }

    private func finalizeAlbum() async {
        isCreatingAlbum = true
        do {
            // 1. Delete all photos marked for deletion in a single batch.
            //    iOS shows exactly one native "Delete N Photos?" confirmation sheet here.
            let deleteResult = PHAsset.fetchAssets(
                withLocalIdentifiers: localSession.toDeletePhotoIDs, options: nil)
            var toDelete: [PHAsset] = []
            deleteResult.enumerateObjects { a, _, _ in toDelete.append(a) }
            if !toDelete.isEmpty {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
                }
                let deletedItems = toDelete.map { asset in
                    DeletedMediaItem(
                        id: UUID(),
                        assetLocalIdentifier: asset.localIdentifier,
                        mediaType: "photo",
                        fileSize: PhotoLibraryService.getFileSize(for: asset),
                        creationDate: asset.creationDate,
                        filename: PhotoLibraryService.getOriginalFilename(for: asset),
                        deletionDate: Date()
                    )
                }
                DeletedItemsStore.shared.addMediaItems(deletedItems)
            }

            if localSession.isAlbumMode {
                // 2. Resolve the album — prefer the one already created at naming time.
                let albumID: String
                if let existingID = localSession.createdAlbumIdentifier,
                   PHAssetCollection.fetchAssetCollections(
                       withLocalIdentifiers: [existingID], options: nil).firstObject != nil {
                    albumID = existingID
                } else {
                    var placeholderID: String?
                    try await PHPhotoLibrary.shared().performChanges {
                        let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                            withTitle: localSession.albumName)
                        placeholderID = req.placeholderForCreatedAssetCollection.localIdentifier
                    }
                    guard let newID = placeholderID else {
                        throw NSError(domain: "AlbumCreation", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Could not create album."])
                    }
                    albumID = newID
                }

                // 3. Add any approved photos not yet in the album.
                let remainingToAdd = localSession.approvedPhotoIDs.filter {
                    !addedToAlbumIDs.contains($0)
                }
                if !remainingToAdd.isEmpty {
                    let albumResult = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [albumID], options: nil)
                    if let album = albumResult.firstObject {
                        let approvedResult = PHAsset.fetchAssets(
                            withLocalIdentifiers: remainingToAdd, options: nil)
                        var approved: [PHAsset] = []
                        approvedResult.enumerateObjects { a, _, _ in approved.append(a) }
                        if !approved.isEmpty {
                            try await PHPhotoLibrary.shared().performChanges {
                                PHAssetCollectionChangeRequest(for: album)?.addAssets(approved as NSArray)
                            }
                        }
                    }
                }

                await MainActor.run {
                    localSession.createdAlbumIdentifier = albumID
                    localSession.state = .completed
                    onUpdate(localSession)
                    isCreatingAlbum = false
                }
            } else {
                await MainActor.run {
                    localSession.state = .completed
                    onUpdate(localSession)
                    isCreatingAlbum = false
                }
            }
        } catch {
            await MainActor.run {
                albumError = error.localizedDescription
                isCreatingAlbum = false
            }
        }
    }
}

// MARK: - Completed

struct AlbumCompletedView: View {
    let session: AlbumCreationSession
    @ObservedObject private var store = AlbumCreationStore.shared
    @Environment(\.dismiss) private var dismiss

    private var skippedAndUntaggedCount: Int {
        let kept = Set(session.approvedPhotoIDs + session.toDeletePhotoIDs)
        return session.swipePhotoIDs.filter { !kept.contains($0) }.count
    }

    var body: some View {
        let isAlbum = session.isAlbumMode
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
            Text(isAlbum ? "\"\(session.albumName)\" created!" : "Sort complete!")
                .font(.title.weight(.bold))
            VStack(spacing: 8) {
                Text(isAlbum
                     ? "\(session.approvedPhotoIDs.count) photos added to the album."
                     : "\(session.approvedPhotoIDs.count) photos kept.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(session.toDeletePhotoIDs.count) photos deleted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if skippedAndUntaggedCount > 0 {
                    Text("\(skippedAndUntaggedCount) skipped or untagged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            Button {
                store.delete(session)
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .navigationTitle(isAlbum ? "Album Created" : "Sort Complete")
    }
}

// MARK: - Skipped & untagged review

struct SkippedPhotosReviewView: View {
    let reviewIDs: [String]
    var isAlbumMode: Bool = true
    /// Called whenever the user applies a new decision. When `nil`, action buttons are hidden
    /// (read-only mode, e.g. when viewing after album completion).
    var onDecision: ((String, AlbumSwipeAction) -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var currentAsset: PHAsset?
    /// Tracks decisions applied in this review session so we can show a badge.
    @State private var localDecisions: [String: AlbumSwipeAction] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Counter
            Text("\(currentIndex + 1) of \(reviewIDs.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

            if let asset = currentAsset {
                ZStack {
                    // Photo — reuse the same card view used in the swipe step
                    CardPhotoView(asset: asset, isDragging: false)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Decision banner at the top (if the user re-tagged this photo)
                    if let decision = localDecisions[asset.localIdentifier] {
                        VStack {
                            decisionBanner(decision)
                                .padding(.top, 8)
                            Spacer()
                        }
                    }

                    // Navigation arrows
                    HStack {
                        if currentIndex > 0 {
                            navArrowButton(systemImage: "chevron.left") { advance(by: -1) }
                        } else {
                            Color.clear.frame(width: 60)
                        }
                        Spacer()
                        if currentIndex < reviewIDs.count - 1 {
                            navArrowButton(systemImage: "chevron.right") { advance(by: 1) }
                        } else {
                            Color.clear.frame(width: 60)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .padding(.horizontal, 12)
                .id(asset.localIdentifier)

                // Metadata
                PhotoMetadataBar(asset: asset)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                // Tag action buttons (only when a callback is provided)
                if onDecision != nil {
                    HStack(spacing: 16) {
                        tagButton(label: "Delete", icon: "trash.fill", color: .red,
                                  isActive: localDecisions[asset.localIdentifier] == .delete) {
                            apply(.delete, to: asset)
                        }
                        tagButton(label: "Skip", icon: "arrow.down.circle.fill", color: .blue,
                                  isActive: localDecisions[asset.localIdentifier] == .skip) {
                            apply(.skip, to: asset)
                        }
                        tagButton(label: isAlbumMode ? "Add" : "Keep", icon: "heart.fill", color: .green,
                                  isActive: localDecisions[asset.localIdentifier] == .approve) {
                            apply(.approve, to: asset)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }

            Spacer(minLength: 8)
        }
        .navigationTitle("Skipped & Untagged")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPhoto(at: 0) }
    }

    @ViewBuilder
    private func decisionBanner(_ decision: AlbumSwipeAction) -> some View {
        let (label, icon, color): (String, String, Color) = {
            switch decision {
            case .approve: return (isAlbumMode ? "Added to album" : "Kept", "heart.fill", .green)
            case .delete:  return ("Marked for deletion", "trash.fill", .red)
            case .skip:    return ("Skipped", "arrow.down.circle.fill", .blue)
            }
        }()
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func tagButton(label: String, icon: String, color: Color,
                           isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isActive ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isActive ? color : color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func navArrowButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Circle().fill(.black.opacity(0.35)))
        }
    }

    private func apply(_ action: AlbumSwipeAction, to asset: PHAsset) {
        let id = asset.localIdentifier
        localDecisions[id] = action
        onDecision?(id, action)
    }

    private func advance(by delta: Int) {
        let next = currentIndex + delta
        guard next >= 0, next < reviewIDs.count else { return }
        currentIndex = next
        loadPhoto(at: next)
    }

    private func loadPhoto(at index: Int) {
        guard index < reviewIDs.count else { currentAsset = nil; return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [reviewIDs[index]], options: nil)
        if let asset = result.firstObject {
            currentAsset = asset
        } else {
            // Asset was deleted externally — skip to the next available one
            advance(by: 1)
        }
    }
}

// MARK: - Swipe card

enum AlbumSwipeAction { case approve, delete, skip }

private enum SwipeDir {
    case right, left, down, none
    var color: Color {
        switch self {
        case .right: return .green
        case .left:  return .red
        case .down:  return .blue
        case .none:  return .clear
        }
    }
    var label: String {
        switch self {
        case .right: return "Add to album"
        case .left:  return "Delete"
        case .down:  return "Skip"
        case .none:  return ""
        }
    }
    var icon: String {
        switch self {
        case .right: return "heart.fill"
        case .left:  return "trash.fill"
        case .down:  return "arrow.down.circle.fill"
        case .none:  return ""
        }
    }
}

struct SwipeCardView: View {
    let asset: PHAsset
    let burstSiblings: [PHAsset]
    let existingDecision: AlbumSwipeAction?
    var isAlbumMode: Bool = true
    let onSwipe: (AlbumSwipeAction) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private let threshold: CGFloat = 100

    private var swipeDir: SwipeDir {
        if dragOffset.width > 60  { return .right }
        if dragOffset.width < -60 { return .left }
        if dragOffset.height > 60 { return .down }
        return .none
    }

    private var rotation: Double { Double(dragOffset.width / 22) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Use a plain image view with no competing gestures.
                CardPhotoView(asset: asset, isDragging: isDragging)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(swipeDir.color.opacity(dragOffset == .zero ? 0 : 0.85), lineWidth: 4)
                    )

                // Previous-decision banner — top of photo, shown when idle
                if let prior = existingDecision, swipeDir == .none {
                    VStack {
                        existingDecisionBanner(prior)
                            .padding(.top, 12)
                        Spacer()
                    }
                }

                // Gesture hint strip — always visible at the bottom when idle
                if swipeDir == .none {
                    VStack {
                        Spacer()
                        HStack(spacing: 0) {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.red)
                            Spacer()
                            Label("Skip", systemImage: "arrow.down")
                                .foregroundStyle(.blue)
                            Spacer()
                            Label(isAlbumMode ? "Add" : "Keep", systemImage: "heart")
                                .foregroundStyle(.green)
                        }
                        .font(.caption.weight(.semibold))
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)
                    }
                }

                // Action overlay during drag
                if swipeDir != .none {
                    VStack {
                        HStack {
                            if swipeDir == .right {
                                Spacer()
                                actionLabel(swipeDir)
                                    .padding(.trailing, 20).padding(.top, 20)
                            }
                            if swipeDir == .left {
                                actionLabel(swipeDir)
                                    .padding(.leading, 20).padding(.top, 20)
                                Spacer()
                            }
                        }
                        if swipeDir == .down {
                            actionLabel(swipeDir).padding(.top, 20)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .rotationEffect(.degrees(rotation))
            .offset(dragOffset)
            // highPriorityGesture ensures drag wins over any child gestures.
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        isDragging = true
                        dragOffset = v.translation
                    }
                    .onEnded { v in
                        isDragging = false
                        commitSwipe(v.translation)
                    }
            )
            .animation(isDragging ? .none : .spring(response: 0.3), value: dragOffset)

        }
    }

    @ViewBuilder
    private func actionLabel(_ dir: SwipeDir) -> some View {
        let label = (dir == .right && !isAlbumMode) ? "Keep" : dir.label
        Label(label, systemImage: dir.icon)
            .font(.headline.weight(.bold))
            .foregroundStyle(dir.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(dir.color.opacity(0.15)))
    }

    @ViewBuilder
    private func existingDecisionBanner(_ decision: AlbumSwipeAction) -> some View {
        let (icon, label, color): (String, String, Color) = {
            switch decision {
            case .approve: return ("heart.fill", isAlbumMode ? "Added to album" : "Kept", .green)
            case .delete:  return ("trash.fill",             "Marked for deletion", .red)
            case .skip:    return ("arrow.down.circle.fill", "Skipped",         .blue)
            }
        }()
        Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func commitSwipe(_ translation: CGSize) {
        let action: AlbumSwipeAction?
        let target: CGSize
        if translation.width > threshold {
            action = .approve
            target = CGSize(width: 1200, height: 0)
        } else if translation.width < -threshold {
            action = .delete
            target = CGSize(width: -1200, height: 0)
        } else if translation.height > threshold {
            action = .skip
            target = CGSize(width: 0, height: 1200)
        } else {
            action = nil
            target = .zero
        }
        guard let action else {
            // Not past threshold — snap back.
            withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
            return
        }
        // Fly card off screen, THEN notify parent. The parent will replace the card via .id(),
        // giving the new card a fresh dragOffset = .zero automatically.
        withAnimation(.easeOut(duration: 0.25)) { dragOffset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwipe(action)
        }
    }
}

/// Loads a full-resolution image for display in the swipe card.
/// No competing gestures — the parent DragGesture owns all touches.
private struct CardPhotoView: View {
    let asset: PHAsset
    /// Passed from the parent SwipeCardView; resets zoom the moment a swipe begins.
    let isDragging: Bool

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()          // show the full photo, no cropping
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay(ProgressView().tint(.secondary))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale, anchor: .center)
            // Pinch-to-zoom — simultaneous with the parent's DragGesture (different fingers)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in
                        scale = min(4.0, max(1.0, lastScale * v))
                    }
                    .onEnded { v in
                        lastScale = scale
                        // Snap back to 1× if under-pinched
                        if scale < 1.05 {
                            withAnimation(.spring(response: 0.3)) {
                                scale = 1.0; lastScale = 1.0
                            }
                        }
                    }
            )
            // Reset zoom the instant the user starts a swipe
            .onChange(of: isDragging) { dragging in
                if dragging && scale > 1 {
                    withAnimation(.spring(response: 0.25)) {
                        scale = 1.0; lastScale = 1.0
                    }
                }
            }
            .task(id: asset.localIdentifier) {
                await loadImage(targetSize: geo.size)
            }
        }
    }

    private func loadImage(targetSize: CGSize) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let screenScale = UIScreen.main.scale
        let size = CGSize(width: targetSize.width * screenScale,
                          height: targetSize.height * screenScale)
        PHImageManager.default().requestImage(
            for: asset, targetSize: size,
            contentMode: .aspectFit, options: options     // match fit content mode
        ) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}

// MARK: - Photo metadata bar

private struct PhotoMetadataBar: View {
    let asset: PHAsset

    private var dateText: String {
        guard let d = asset.creationDate else { return "Unknown date" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private var sizeText: String {
        let bytes = PhotoLibraryService.getFileSize(for: asset)
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb)
                       : String(format: "%d KB", Int(bytes / 1024))
    }

    private var dimensionsText: String {
        guard asset.pixelWidth > 0 else { return "" }
        return "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }

    var body: some View {
        HStack(spacing: 0) {
            metaItem(icon: "calendar", text: dateText)
            if !sizeText.isEmpty {
                dot
                metaItem(icon: "doc", text: sizeText)
            }
            if !dimensionsText.isEmpty {
                dot
                metaItem(icon: "rectangle.dashed", text: dimensionsText)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var dot: some View {
        Text("·")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func metaItem(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - Edit bar

private struct PhotoEditBar: View {
    let asset: PHAsset
    let onEditApplied: () -> Void

    @State private var isBusy = false
    @State private var showCrop = false
    @State private var errorMsg: String?

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            editButton(icon: "rotate.right", label: "Rotate") {
                Task { await rotate() }
            }
            Spacer()
            editButton(icon: "crop", label: "Crop") {
                showCrop = true
            }
            Spacer()
            if isBusy {
                ProgressView().scaleEffect(0.75)
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(isBusy)
        .sheet(isPresented: $showCrop) {
            CropPhotoView(asset: asset) { onEditApplied() }
        }
        .alert("Edit failed", isPresented: .constant(errorMsg != nil)) {
            Button("OK") { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
    }

    @ViewBuilder
    private func editButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
        }
        .foregroundStyle(.primary)
    }

    private func rotate() async {
        isBusy = true

        let opts = PHContentEditingInputRequestOptions()
        opts.isNetworkAccessAllowed = true
        let input: PHContentEditingInput? = await withCheckedContinuation { cont in
            asset.requestContentEditingInput(with: opts) { i, _ in cont.resume(returning: i) }
        }
        guard let input, let srcURL = input.fullSizeImageURL else {
            await MainActor.run { isBusy = false }
            return
        }

        let output = PHContentEditingOutput(contentEditingInput: input)
        let destURL = output.renderedContentURL
        let capturedAsset = asset

        // Run on a background queue — avoids blocking the UI and reduces peak memory
        // by using CGImageSource → CGImageDestination (single decode/encode pass,
        // EXIF orientation updated without rotating pixels).
        let writeError: String? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil) else {
                    cont.resume(returning: "Could not read image source.")
                    return
                }
                var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
                             as? [CFString: Any]) ?? [:]
                let cur = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
                props[kCGImagePropertyOrientation] = Self.cwExifOrientation(cur)
                props[kCGImageDestinationLossyCompressionQuality] = 0.92

                guard let dest = CGImageDestinationCreateWithURL(
                    destURL as CFURL, "public.jpeg" as CFString, 1, nil
                ) else {
                    cont.resume(returning: "Could not create output destination.")
                    return
                }
                CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
                guard CGImageDestinationFinalize(dest) else {
                    cont.resume(returning: "Could not write rotated image.")
                    return
                }
                cont.resume(returning: nil)
            }
        }

        if let err = writeError {
            await MainActor.run { isBusy = false; errorMsg = err }
            return
        }

        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: "com.deedoop.edit",
            formatVersion: "1.0",
            data: Data("rotate90cw".utf8)
        )
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: capturedAsset).contentEditingOutput = output
            }
            await MainActor.run { isBusy = false; onEditApplied() }
        } catch {
            await MainActor.run { isBusy = false; errorMsg = error.localizedDescription }
        }
    }

    /// Maps an EXIF orientation value to the result of rotating 90° clockwise.
    private static func cwExifOrientation(_ o: UInt32) -> UInt32 {
        switch o {
        case 1: return 6;  case 6: return 3;  case 3: return 8;  case 8: return 1
        case 2: return 5;  case 5: return 4;  case 4: return 7;  case 7: return 2
        default: return 6
        }
    }
}

// MARK: - Crop view

private struct CropPhotoView: View {
    let asset: PHAsset
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayImage: UIImage?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMsg: String?

    /// Crop rectangle in the view's coordinate space.
    @State private var cropRect: CGRect = .zero
    /// The rect where the image actually sits (scaledToFit inside the container).
    @State private var displayRect: CGRect = .zero

    private let minCropPt: CGFloat = 60

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if isLoading {
                    ProgressView("Loading…").tint(.white)
                } else if let img = displayImage {
                    GeometryReader { geo in
                        let imgR = fitRect(img: img, in: geo.size)
                        ZStack {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)

                            if cropRect != .zero {
                                // Dim area outside crop
                                CropMaskShape(cropRect: cropRect)
                                    .fill(.black.opacity(0.55),
                                          style: FillStyle(eoFill: true))
                                    .allowsHitTesting(false)

                                // Crop border
                                Rectangle()
                                    .strokeBorder(.white, lineWidth: 1.5)
                                    .frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                                    .allowsHitTesting(false)

                                // Draggable corner handles
                                cropHandle(.topLeft)
                                cropHandle(.topRight)
                                cropHandle(.bottomLeft)
                                cropHandle(.bottomRight)
                            }
                        }
                        .onAppear {
                            displayRect = imgR
                            if cropRect == .zero { cropRect = imgR }
                        }
                        .onChange(of: imgR) { newR in
                            displayRect = newR
                            cropRect = newR
                        }
                    }
                } else {
                    Text("Could not load image").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.orange)
                    } else {
                        Button("Apply") { Task { await applyCrop() } }
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .task { loadDisplayImage() }
        .alert("Could not save", isPresented: .constant(errorMsg != nil)) {
            Button("OK") { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
    }

    // MARK: Corner handles

    private enum CropCorner { case topLeft, topRight, bottomLeft, bottomRight }

    @ViewBuilder
    private func cropHandle(_ corner: CropCorner) -> some View {
        let pos: CGPoint = {
            switch corner {
            case .topLeft:     return CGPoint(x: cropRect.minX, y: cropRect.minY)
            case .topRight:    return CGPoint(x: cropRect.maxX, y: cropRect.minY)
            case .bottomLeft:  return CGPoint(x: cropRect.minX, y: cropRect.maxY)
            case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
            }
        }()
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .position(pos)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in moveCrop(corner: corner, to: v.location) }
            )
    }

    private func moveCrop(corner: CropCorner, to pt: CGPoint) {
        let cx = max(displayRect.minX, min(displayRect.maxX, pt.x))
        let cy = max(displayRect.minY, min(displayRect.maxY, pt.y))
        var r = cropRect
        switch corner {
        case .topLeft:
            let nw = max(minCropPt, r.maxX - cx), nh = max(minCropPt, r.maxY - cy)
            r.origin = CGPoint(x: r.maxX - nw, y: r.maxY - nh)
            r.size   = CGSize(width: nw, height: nh)
        case .topRight:
            let nh = max(minCropPt, r.maxY - cy)
            r.origin.y = r.maxY - nh
            r.size = CGSize(width: max(minCropPt, cx - r.minX), height: nh)
        case .bottomLeft:
            let nw = max(minCropPt, r.maxX - cx)
            r.origin.x = r.maxX - nw
            r.size = CGSize(width: nw, height: max(minCropPt, cy - r.minY))
        case .bottomRight:
            r.size = CGSize(width:  max(minCropPt, cx - r.minX),
                            height: max(minCropPt, cy - r.minY))
        }
        cropRect = r
    }

    // MARK: Helpers

    private func fitRect(img: UIImage, in size: CGSize) -> CGRect {
        let scale = min(size.width / img.size.width, size.height / img.size.height)
        let w = img.size.width * scale, h = img.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    // MARK: Load / Save

    private func loadDisplayImage() {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        let side = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit,
            options: opts
        ) { img, info in
            guard let img else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in
                if !degraded || self.displayImage == nil {
                    self.displayImage = img
                    self.isLoading = false
                }
            }
        }
    }

    private func applyCrop() async {
        guard displayRect.width > 0 else { return }
        isSaving = true

        // Load the full-size original for pixel-accurate cropping.
        let editOpts = PHContentEditingInputRequestOptions()
        editOpts.isNetworkAccessAllowed = true
        let input: PHContentEditingInput? = await withCheckedContinuation { cont in
            asset.requestContentEditingInput(with: editOpts) { i, _ in cont.resume(returning: i) }
        }
        guard let input,
              let url = input.fullSizeImageURL,
              let raw = UIImage(contentsOfFile: url.path) else {
            await MainActor.run { isSaving = false; errorMsg = "Could not load original image." }
            return
        }
        let fullImg = raw.normalizedOrientation()

        // Map from view coords → pixel coords.
        let sx = fullImg.size.width  / displayRect.width
        let sy = fullImg.size.height / displayRect.height
        let pixelCrop = CGRect(
            x: (cropRect.minX - displayRect.minX) * sx,
            y: (cropRect.minY - displayRect.minY) * sy,
            width:  cropRect.width  * sx,
            height: cropRect.height * sy
        ).intersection(CGRect(origin: .zero, size: fullImg.size))

        guard let cgCropped = fullImg.cgImage?.cropping(to: pixelCrop),
              let data = UIImage(cgImage: cgCropped).jpegData(compressionQuality: 0.92) else {
            await MainActor.run { isSaving = false; errorMsg = "Crop failed." }
            return
        }

        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: "com.deedoop.edit",
            formatVersion: "1.0",
            data: Data("crop".utf8)
        )
        do {
            try data.write(to: output.renderedContentURL)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: self.asset).contentEditingOutput = output
            }
            await MainActor.run { isSaving = false; onDone(); dismiss() }
        } catch {
            await MainActor.run { isSaving = false; errorMsg = error.localizedDescription }
        }
    }
}

private struct CropMaskShape: Shape {
    let cropRect: CGRect
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRect(cropRect)
        return p
    }
}

// MARK: - Film strip

private enum FilmStripStatus { case pending, approved, deleted, skipped }

/// A scrollable horizontal strip of all photos in the swipe roll.
/// Auto-scrolls to keep the current photo centred. Tap any thumbnail to navigate.
private struct SwipeFilmStrip: View {
    let swipePhotoIDs: [String]
    let currentIndex: Int
    let approvedIDs: Set<String>
    let skippedIDs: Set<String>
    let toDeleteIDs: Set<String>
    let burstSiblingIDs: Set<String>
    let onNavigate: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 5) {
                        ForEach(Array(swipePhotoIDs.enumerated()), id: \.offset) { index, id in
                            FilmStripThumbnail(
                                assetID: id,
                                isCurrent: index == currentIndex,
                                status: status(for: id),
                                isBurstSibling: burstSiblingIDs.contains(id)
                            )
                            .id(index)
                            .onTapGesture { onNavigate(index) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(height: 84)
                .onChange(of: currentIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    private func status(for id: String) -> FilmStripStatus {
        if approvedIDs.contains(id) { return .approved }
        if toDeleteIDs.contains(id) { return .deleted }
        if skippedIDs.contains(id)  { return .skipped }
        return .pending
    }
}

/// A single thumbnail in the film strip.
private struct FilmStripThumbnail: View {
    let assetID: String
    let isCurrent: Bool
    let status: FilmStripStatus
    var isBurstSibling: Bool = false

    @State private var image: UIImage?
    /// True when the asset no longer exists in the Photos library (deleted in a past session).
    @State private var assetMissing = false

    private let size: CGFloat = 64

    var body: some View {
        // Collapse to nothing if the photo has been deleted from the library.
        if !assetMissing {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.secondary)
                        )
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Burst / current border
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isCurrent      ? Color.orange :
                        isBurstSibling ? Color.cyan.opacity(0.85) : Color.clear,
                        lineWidth: isCurrent ? 3 : 2
                    )
            )
            // Burst tint
            .overlay(
                isBurstSibling && !isCurrent
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.18))
                    : nil
            )
            // Dim processed photos
            .overlay(
                status != .pending && !isCurrent
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3))
                    : nil
            )
            // Top-left: favourite heart
            .overlay(alignment: .topLeading) {
                if isFavourite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(Color.pink.opacity(0.85)))
                        .padding(3)
                }
            }
            // Bottom-right: swipe-decision badge
            .overlay(alignment: .bottomTrailing) {
                if status != .pending {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(badgeColor))
                        .padding(3)
                }
            }
            .task(id: assetID) { await loadThumb() }
            .transition(.opacity)
        }
    }

    private var isFavourite: Bool {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        return result.firstObject?.isFavorite ?? false
    }

    private var badgeIcon: String {
        switch status {
        case .approved: return "heart.fill"
        case .deleted:  return "trash.fill"
        case .skipped:  return "arrow.down"
        case .pending:  return ""
        }
    }

    private var badgeColor: Color {
        switch status {
        case .approved: return .green
        case .deleted:  return .red
        case .skipped:  return .blue
        case .pending:  return .clear
        }
    }

    private func loadThumb() async {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else {
            // Asset no longer exists — was deleted in a previous session.
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { assetMissing = true }
            }
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let px = Int(size * UIScreen.main.scale)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: px, height: px),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}

// MARK: - Shared session row label

private struct SessionRowLabel: View {
    let session: AlbumCreationSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.state == .completed ? "checkmark.circle.fill" : iconName)
                .font(.title2)
                .foregroundStyle(session.state == .completed ? .green : accentColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((session.state == .completed ? Color.green : accentColor).opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(session.progressSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String { session.isAlbumMode ? "photo.stack" : "arrow.left.arrow.right.square" }
    private var accentColor: Color { session.isAlbumMode ? .orange : .indigo }
}

// MARK: - Sort Photos flow (mirrors AlbumCreationFlowView but no album)

struct SortPhotosFlowView: View {
    @ObservedObject private var store = AlbumCreationStore.shared
    @State private var activeSession: AlbumCreationSession?

    private var sortSessions: [AlbumCreationSession] {
        store.sessions.filter { !$0.isAlbumMode }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)

            if sortSessions.isEmpty && activeSession == nil {
                emptyState
            } else {
                sessionList
            }
        }
        .navigationTitle("Sort Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let s = AlbumCreationSession.newSort()
                    store.upsert(s)
                    activeSession = s
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { activeSession != nil },
            set: { if !$0 {
                // Discard sessions that never had dates set
                if let s = activeSession, s.startDate == nil {
                    store.delete(s)
                }
                activeSession = nil
            }}
        )) {
            if let session = activeSession {
                AlbumSessionCoordinatorView(sessionID: session.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right.square")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No sorting sessions")
                .font(.title2.weight(.semibold))
            Text("Tap + to start sorting photos from a date range.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                let s = AlbumCreationSession.newSort()
                store.upsert(s)
                activeSession = s
            } label: {
                Label("Start sorting", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sortSessions) { session in
                Button {
                    activeSession = session
                } label: {
                    SessionRowLabel(session: session)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                indexSet.forEach { store.delete(sortSessions[$0]) }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - PHPicker wrapper

struct SinglePhotoPickerView: UIViewControllerRepresentable {
    let onPick: (String, Date) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SinglePhotoPickerView
        init(_ parent: SinglePhotoPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first, let identifier = result.assetIdentifier else {
                parent.onCancel()
                return
            }
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                parent.onCancel()
                return
            }
            let date = asset.creationDate ?? Date()
            parent.onPick(identifier, date)
        }
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    /// Returns a copy with the orientation baked into the pixel data (always .up).
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Returns a new image rotated 90° clockwise.
    func rotated90Clockwise() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        return UIGraphicsImageRenderer(size: newSize).image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            ctx.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

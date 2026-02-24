//
//  PhotoLibraryService.swift
//  DeeDoop
//

import Combine
import Photos

/// Service for fetching photos/videos from the photo library and detecting duplicates.
final class PhotoLibraryService: ObservableObject {
    
    enum MediaFilter {
        case photosOnly
        case videosOnly
    }
    
    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    struct VideoBySizeItem: Identifiable {
        let id: String
        let asset: PHAsset
        let fileSize: Int64
        let creationDate: Date?
        let duration: TimeInterval
    }
    
    @Published private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var photoDuplicateGroups: [DuplicateGroup] = []
    @Published private(set) var videoDuplicateGroups: [DuplicateGroup] = []
    @Published private(set) var photoBurstGroups: [DuplicateGroup] = []
    @Published private(set) var videosBySizeItems: [VideoBySizeItem] = []
    @Published private(set) var scanError: String?
    
    /// All duplicate groups (photos + videos) for convenience.
    var duplicateGroups: [DuplicateGroup] { photoDuplicateGroups + videoDuplicateGroups }
    
    private let photoLibrary = PHPhotoLibrary.shared()
    
    init() {
        updateAuthorizationStatus()
    }
    
    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.updateAuthorizationStatus()
            }
        }
    }
    
    private func updateAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .authorized, .limited:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .restricted:
            authorizationStatus = .restricted
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }
    
    
    /// Scan for duplicates in the given date range. Use mediaFilter to scan only photos or only videos.
    func scanForDuplicates(from startDate: Date, to endDate: Date, mediaFilter: MediaFilter) async {
        await MainActor.run {
            isScanning = true
            scanProgress = 0
            scanError = nil
            photoDuplicateGroups = []
            videoDuplicateGroups = []
            photoBurstGroups = []
            videosBySizeItems = []
        }
        
        let predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = predicate
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        var photoGroups: [DuplicateGroup] = []
        var videoGroups: [DuplicateGroup] = []
        var burstGroups: [DuplicateGroup] = []
        var videoSizeItems: [VideoBySizeItem] = []
        
        if mediaFilter == .photosOnly {
            let imageResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var photoSignatureToAssets: [String: [PHAsset]] = [:]

            // Track potential bursts: clusters of photos taken within a few seconds of each other.
            let burstThreshold: TimeInterval = 3 // seconds
            var currentBurst: [PHAsset] = []
            var burstClusters: [[PHAsset]] = []

            let total = max(imageResult.count, 1)
            var processed = 0

            imageResult.enumerateObjects { asset, _, _ in
                let fileSize = Self.getFileSize(for: asset)
                let creationDate = asset.creationDate ?? Date.distantPast
                let dateString = dateFormatter.string(from: creationDate)
                let w = asset.pixelWidth
                let h = asset.pixelHeight
                let filename = Self.getOriginalFilename(for: asset) ?? ""
                let signature = "photo_\(fileSize)_\(dateString)_\(w)_\(h)_\(filename)"
                photoSignatureToAssets[signature, default: []].append(asset)

                // Build burst clusters based on temporal proximity.
                if let date = asset.creationDate {
                    if let last = currentBurst.last, let lastDate = last.creationDate {
                        let delta = abs(date.timeIntervalSince(lastDate))
                        if delta <= burstThreshold {
                            currentBurst.append(asset)
                        } else {
                            if currentBurst.count >= 3 {
                                burstClusters.append(currentBurst)
                            }
                            currentBurst = [asset]
                        }
                    } else {
                        currentBurst = [asset]
                    }
                } else {
                    if currentBurst.count >= 3 {
                        burstClusters.append(currentBurst)
                    }
                    currentBurst.removeAll()
                }

                processed += 1
                if processed % 10 == 0 || processed == total {
                    let fraction = Double(processed) / Double(total)
                    DispatchQueue.main.async {
                        self.scanProgress = min(fraction, 0.99)
                    }
                }
            }
            // Flush last burst cluster if valid.
            if currentBurst.count >= 3 {
                burstClusters.append(currentBurst)
            }

            photoGroups = photoSignatureToAssets
                .filter { $0.value.count >= 2 }
                .map { signature, assets in
                    DuplicateGroup(
                        id: signature,
                        assets: assets,
                        fileSize: Self.getFileSize(for: assets.first!),
                        creationDate: assets.first?.creationDate,
                        mediaType: .image
                    )
                }
                .sorted { $0.assets.count > $1.assets.count }

            burstGroups = burstClusters.enumerated().compactMap { index, assets in
                guard let first = assets.first else { return nil }
                return DuplicateGroup(
                    id: "burst_\(index)_\(first.localIdentifier)",
                    assets: assets,
                    fileSize: Self.getFileSize(for: first),
                    creationDate: first.creationDate,
                    mediaType: .image
                )
            }
            .sorted { $0.assets.count > $1.assets.count }
        }
        
        if mediaFilter == .videosOnly {
            let videoResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            var videoSignatureToAssets: [String: [PHAsset]] = [:]

            let total = max(videoResult.count, 1)
            var processed = 0

            videoResult.enumerateObjects { asset, _, _ in
                let fileSize = Self.getFileSize(for: asset)
                let creationDate = asset.creationDate ?? Date.distantPast
                let dateString = dateFormatter.string(from: creationDate)
                let duration = asset.duration
                let filename = Self.getOriginalFilename(for: asset) ?? ""
                let signature = "video_\(fileSize)_\(dateString)_\(duration)_\(filename)"
                videoSignatureToAssets[signature, default: []].append(asset)

                // Track all videos for the "by size" view.
                let item = VideoBySizeItem(
                    id: asset.localIdentifier,
                    asset: asset,
                    fileSize: fileSize,
                    creationDate: asset.creationDate,
                    duration: duration
                )
                videoSizeItems.append(item)

                processed += 1
                if processed % 10 == 0 || processed == total {
                    let fraction = Double(processed) / Double(total)
                    DispatchQueue.main.async {
                        self.scanProgress = min(fraction, 0.99)
                    }
                }
            }
            videoGroups = videoSignatureToAssets
                .filter { $0.value.count >= 2 }
                .map { signature, assets in
                    DuplicateGroup(
                        id: signature,
                        assets: assets,
                        fileSize: Self.getFileSize(for: assets.first!),
                        creationDate: assets.first?.creationDate,
                        mediaType: .video
                    )
                }
                .sorted { $0.assets.count > $1.assets.count }

            // Sort all videos by size (largest first) for the "by size" feature.
            videoSizeItems.sort { $0.fileSize > $1.fileSize }
        }
        
        await MainActor.run {
            photoDuplicateGroups = photoGroups
            videoDuplicateGroups = videoGroups
            photoBurstGroups = burstGroups
            videosBySizeItems = videoSizeItems
            isScanning = false
            scanProgress = 1
        }
    }
    
    /// Get file size for a PHAsset using PHAssetResource.
    static func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        let fullSizeResource = resources.first { resource in
            resource.type == .photo || resource.type == .video || resource.type == .alternatePhoto
        }
        let resource = fullSizeResource ?? resources.first
        guard let res = resource else { return 0 }
        let size = res.value(forKey: "fileSize") as? Int64 ?? 0
        return size
    }
    
    /// Original filename from the asset's resource, when available.
    static func getOriginalFilename(for asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        let main = resources.first { $0.type == .photo || $0.type == .video || $0.type == .alternatePhoto }
        return (main ?? resources.first)?.originalFilename
    }
    
    /// Delete the given assets from the photo library (keeps one, removes the rest).
    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await photoLibrary.performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    /// Delete selected videos from the "videos by size" list.
    func deleteVideosBySizeItems(withIDs ids: Set<String>) async throws {
        let itemsToDelete = videosBySizeItems.filter { ids.contains($0.id) }
        guard !itemsToDelete.isEmpty else { return }

        let assets = itemsToDelete.map(\.asset)
        let deletedItems = itemsToDelete.map { item in
            DeletedMediaItem(
                id: UUID(),
                assetLocalIdentifier: item.asset.localIdentifier,
                mediaType: "video",
                fileSize: item.fileSize,
                creationDate: item.creationDate,
                filename: Self.getOriginalFilename(for: item.asset),
                deletionDate: Date()
            )
        }
        DeletedItemsStore.shared.addMediaItems(deletedItems)

        try await deleteAssets(assets)
        await MainActor.run {
            videosBySizeItems.removeAll { ids.contains($0.id) }
        }
    }
    
    /// Remove duplicate group: keep asset at keepIndex, delete the rest.
    func removeDuplicates(keepingAssetAt keepIndex: Int, in group: DuplicateGroup) async throws {
        try await removeDuplicates(keepingIndices: [keepIndex], in: group)
    }

    /// Remove a group of assets while keeping the assets at the given indices (used for bursts and duplicates).
    func removeDuplicates(keepingIndices: Set<Int>, in group: DuplicateGroup) async throws {
        let toDelete = group.assets.enumerated().compactMap { index, asset in
            keepingIndices.contains(index) ? nil : asset
        }
        let deletedItems = toDelete.map { asset in
            DeletedMediaItem(
                id: UUID(),
                assetLocalIdentifier: asset.localIdentifier,
                mediaType: asset.mediaType == .video ? "video" : "photo",
                fileSize: Self.getFileSize(for: asset),
                creationDate: asset.creationDate,
                filename: Self.getOriginalFilename(for: asset),
                deletionDate: Date()
            )
        }
        DeletedItemsStore.shared.addMediaItems(deletedItems)

        try await deleteAssets(toDelete)
        await MainActor.run {
            if group.mediaType == .image {
                photoDuplicateGroups.removeAll { $0.id == group.id }
                photoBurstGroups.removeAll { $0.id == group.id }
            } else {
                videoDuplicateGroups.removeAll { $0.id == group.id }
            }
        }
    }

    /// Delete every item in the group (all copies). Removes the group from the list.
    func deleteAllInGroup(_ group: DuplicateGroup) async throws {
        let deletedItems = group.assets.map { asset in
            DeletedMediaItem(
                id: UUID(),
                assetLocalIdentifier: asset.localIdentifier,
                mediaType: asset.mediaType == .video ? "video" : "photo",
                fileSize: Self.getFileSize(for: asset),
                creationDate: asset.creationDate,
                filename: Self.getOriginalFilename(for: asset),
                deletionDate: Date()
            )
        }
        DeletedItemsStore.shared.addMediaItems(deletedItems)

        try await deleteAssets(group.assets)
        await MainActor.run {
            if group.mediaType == .image {
                photoDuplicateGroups.removeAll { $0.id == group.id }
            } else {
                videoDuplicateGroups.removeAll { $0.id == group.id }
            }
        }
    }
    
    /// Remove all duplicate groups (photos and videos): keep the first item in each group, delete the rest.
    func removeAllDuplicatesKeepingFirst() async throws {
        let photoGroups = photoDuplicateGroups
        let videoGroups = videoDuplicateGroups
        for group in photoGroups {
            guard !group.assets.isEmpty else { continue }
            let toDelete = Array(group.assets.dropFirst())
            let deletedItems = toDelete.map { asset in
                DeletedMediaItem(
                    id: UUID(),
                    assetLocalIdentifier: asset.localIdentifier,
                    mediaType: asset.mediaType == .video ? "video" : "photo",
                    fileSize: Self.getFileSize(for: asset),
                    creationDate: asset.creationDate,
                    filename: Self.getOriginalFilename(for: asset),
                    deletionDate: Date()
                )
            }
            DeletedItemsStore.shared.addMediaItems(deletedItems)
            try await deleteAssets(toDelete)
        }
        for group in videoGroups {
            guard !group.assets.isEmpty else { continue }
            let toDelete = Array(group.assets.dropFirst())
            let deletedItems = toDelete.map { asset in
                DeletedMediaItem(
                    id: UUID(),
                    assetLocalIdentifier: asset.localIdentifier,
                    mediaType: asset.mediaType == .video ? "video" : "photo",
                    fileSize: Self.getFileSize(for: asset),
                    creationDate: asset.creationDate,
                    filename: Self.getOriginalFilename(for: asset),
                    deletionDate: Date()
                )
            }
            DeletedItemsStore.shared.addMediaItems(deletedItems)
            try await deleteAssets(toDelete)
        }
        await MainActor.run {
            let photoIds = Set(photoGroups.map(\.id))
            let videoIds = Set(videoGroups.map(\.id))
            photoDuplicateGroups.removeAll { photoIds.contains($0.id) }
            videoDuplicateGroups.removeAll { videoIds.contains($0.id) }
        }
    }
}

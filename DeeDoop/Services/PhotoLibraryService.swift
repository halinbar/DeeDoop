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
    
    @Published private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var photoDuplicateGroups: [DuplicateGroup] = []
    @Published private(set) var videoDuplicateGroups: [DuplicateGroup] = []
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
        
        if mediaFilter == .photosOnly {
            let imageResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var photoSignatureToAssets: [String: [PHAsset]] = [:]
            imageResult.enumerateObjects { asset, _, _ in
                let fileSize = Self.getFileSize(for: asset)
                let creationDate = asset.creationDate ?? Date.distantPast
                let dateString = dateFormatter.string(from: creationDate)
                let w = asset.pixelWidth
                let h = asset.pixelHeight
                let filename = Self.getOriginalFilename(for: asset) ?? ""
                let signature = "photo_\(fileSize)_\(dateString)_\(w)_\(h)_\(filename)"
                photoSignatureToAssets[signature, default: []].append(asset)
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
        }
        
        if mediaFilter == .videosOnly {
            let videoResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)
            var videoSignatureToAssets: [String: [PHAsset]] = [:]
            videoResult.enumerateObjects { asset, _, _ in
                let fileSize = Self.getFileSize(for: asset)
                let creationDate = asset.creationDate ?? Date.distantPast
                let dateString = dateFormatter.string(from: creationDate)
                let duration = asset.duration
                let filename = Self.getOriginalFilename(for: asset) ?? ""
                let signature = "video_\(fileSize)_\(dateString)_\(duration)_\(filename)"
                videoSignatureToAssets[signature, default: []].append(asset)
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
        }
        
        await MainActor.run {
            photoDuplicateGroups = photoGroups
            videoDuplicateGroups = videoGroups
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
    
    /// Remove duplicate group: keep asset at keepIndex, delete the rest.
    func removeDuplicates(keepingAssetAt keepIndex: Int, in group: DuplicateGroup) async throws {
        let toDelete = group.assets.enumerated().filter { $0.offset != keepIndex }.map(\.element)
        try await deleteAssets(toDelete)
        await MainActor.run {
            if group.mediaType == .image {
                photoDuplicateGroups.removeAll { $0.id == group.id }
            } else {
                videoDuplicateGroups.removeAll { $0.id == group.id }
            }
        }
    }

    /// Delete every item in the group (all copies). Removes the group from the list.
    func deleteAllInGroup(_ group: DuplicateGroup) async throws {
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
            let toDelete = group.assets.dropFirst()
            try await deleteAssets(Array(toDelete))
        }
        for group in videoGroups {
            guard !group.assets.isEmpty else { continue }
            let toDelete = group.assets.dropFirst()
            try await deleteAssets(Array(toDelete))
        }
        await MainActor.run {
            let photoIds = Set(photoGroups.map(\.id))
            let videoIds = Set(videoGroups.map(\.id))
            photoDuplicateGroups.removeAll { photoIds.contains($0.id) }
            videoDuplicateGroups.removeAll { videoIds.contains($0.id) }
        }
    }
}

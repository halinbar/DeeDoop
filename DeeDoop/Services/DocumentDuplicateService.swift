//
//  DocumentDuplicateService.swift
//  DeeDoop
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Scans a folder for duplicate files (by size + creation date) and supports removing them.
final class DocumentDuplicateService: ObservableObject {

    struct FileBySizeItem: Identifiable {
        let id: String        // file path used as stable ID
        let url: URL
        let fileSize: Int64
        let creationDate: Date?
    }

    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var duplicateGroups: [FileDuplicateGroup] = []
    @Published private(set) var filesBySizeItems: [FileBySizeItem] = []
    @Published private(set) var scanError: String?
    
    private var securityScopedURL: URL?
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private let trashFolderURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let trash = base.appendingPathComponent("DeeDoopTrash", isDirectory: true)
        if !fm.fileExists(atPath: trash.path) {
            try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        }
        trashFolderURL = trash
    }
    
    /// Call when the user has selected a folder (security-scoped URL). Scans for duplicates.
    func scanForDuplicates(in directoryURL: URL) async {
        guard directoryURL.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                scanError = "Could not access the selected folder."
            }
            return
        }
        securityScopedURL = directoryURL
        
        await MainActor.run {
            isScanning = true
            scanProgress = 0
            scanError = nil
            duplicateGroups = []
            filesBySizeItems = []
        }
        
        let fileManager = FileManager.default
        var allFiles: [(url: URL, size: Int64, date: Date)] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            await MainActor.run {
                isScanning = false
                scanError = "Could not read folder contents."
            }
            return
        }
        
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64 ?? (attrs[.size] as? NSNumber)?.int64Value,
                  let date = attrs[.creationDate] as? Date else { continue }
            
            allFiles.append((url: fileURL, size: size, date: date))
        }
        
        // Group by (size, creationDate)
        var signatureToURLs: [String: [URL]] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        
        for item in allFiles {
            let dateString = formatter.string(from: item.date)
            let signature = "\(item.size)_\(dateString)"
            signatureToURLs[signature, default: []].append(item.url)
        }
        
        let groups = signatureToURLs
            .filter { $0.value.count >= 2 }
            .compactMap { signature, urls -> FileDuplicateGroup? in
                guard let firstURL = urls.first,
                      let attrs = try? fileManager.attributesOfItem(atPath: firstURL.path),
                      let size = (attrs[.size] as? NSNumber)?.int64Value ?? (attrs[.size] as? Int64),
                      let date = attrs[.creationDate] as? Date else { return nil }
                return FileDuplicateGroup(
                    id: signature,
                    fileURLs: urls,
                    fileSize: size,
                    creationDate: date
                )
            }
            .sorted { $0.fileURLs.count > $1.fileURLs.count }
        
        // Build "by size" list: all files sorted largest first.
        let sizeItems = allFiles
            .map { FileBySizeItem(id: $0.url.path, url: $0.url, fileSize: $0.size, creationDate: $0.date) }
            .sorted { $0.fileSize > $1.fileSize }

        await MainActor.run {
            duplicateGroups = groups
            filesBySizeItems = sizeItems
            isScanning = false
            scanProgress = 1
        }
    }
    
    /// Remove duplicates: keep file at keepIndex, delete the rest.
    func removeDuplicates(keepingFileAt keepIndex: Int, in group: FileDuplicateGroup) throws {
        var trashed: [TrashedFileItem] = []
        for (index, url) in group.fileURLs.enumerated() where index != keepIndex {
            if let item = try moveFileToTrash(from: url) {
                trashed.append(item)
            }
        }
        DeletedItemsStore.shared.addFileItems(trashed)
        Task { @MainActor in
            duplicateGroups.removeAll { $0.id == group.id }
        }
    }
    
    /// Delete every file in the group (all copies). Removes the group from the list.
    func deleteAllInGroup(_ group: FileDuplicateGroup) throws {
        var trashed: [TrashedFileItem] = []
        for url in group.fileURLs {
            if let item = try moveFileToTrash(from: url) {
                trashed.append(item)
            }
        }
        DeletedItemsStore.shared.addFileItems(trashed)
        Task { @MainActor in
            duplicateGroups.removeAll { $0.id == group.id }
        }
    }

    /// Remove all duplicate groups: keep the first file in each group.
    func removeAllDuplicatesKeepingFirst() throws {
        let groups = duplicateGroups
        var trashed: [TrashedFileItem] = []
        for group in groups {
            for url in group.fileURLs.dropFirst() {
                if let item = try moveFileToTrash(from: url) {
                    trashed.append(item)
                }
            }
        }
        DeletedItemsStore.shared.addFileItems(trashed)
        let idsToRemove = Set(groups.map(\.id))
        Task { @MainActor in
            duplicateGroups.removeAll { idsToRemove.contains($0.id) }
        }
    }
    
    /// Move the files for the given IDs to trash and remove them from the by-size list.
    func deleteFilesBySizeItems(withIDs ids: Set<String>) throws {
        let itemsToDelete = filesBySizeItems.filter { ids.contains($0.id) }
        guard !itemsToDelete.isEmpty else { return }

        var trashed: [TrashedFileItem] = []
        for item in itemsToDelete {
            if let trashedItem = try moveFileToTrash(from: item.url) {
                trashed.append(trashedItem)
            }
        }
        DeletedItemsStore.shared.addFileItems(trashed)
        Task { @MainActor in
            filesBySizeItems.removeAll { ids.contains($0.id) }
        }
    }

    /// Call when done with the selected folder (e.g. leaving the flow).
    func stopAccessingSecurityScopedResource() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
    
    // MARK: - Private: move files into app-managed trash folder

    private func moveFileToTrash(from url: URL) throws -> TrashedFileItem? {
        let fm = FileManager.default

        // If the file no longer exists, skip.
        guard fm.fileExists(atPath: url.path) else { return nil }

        // Compute a unique name in trash.
        let originalName = url.lastPathComponent
        var destination = trashFolderURL.appendingPathComponent(originalName)
        var counter = 1
        while fm.fileExists(atPath: destination.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let suffix = " (\(counter))"
            let newName = ext.isEmpty ? base + suffix : base + suffix + ".\(ext)"
            destination = trashFolderURL.appendingPathComponent(newName)
            counter += 1
        }

        var coordinationError: NSError?
        var moveError: NSError?
        fileCoordinator.coordinate(writingItemAt: url, options: .forMoving, error: &coordinationError) { coordinatedURL in
            do {
                try fm.moveItem(at: coordinatedURL, to: destination)
            } catch let err as NSError {
                moveError = err
            }
        }
        if let error = moveError ?? coordinationError {
            throw error
        }

        let attrs = try fm.attributesOfItem(atPath: destination.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? (attrs[.size] as? Int64) ?? 0
        let date = attrs[.creationDate] as? Date

        return TrashedFileItem(
            id: UUID(),
            originalPath: url.path,
            fileName: destination.lastPathComponent,
            fileSize: size,
            creationDate: date,
            deletionDate: Date()
        )
    }
}

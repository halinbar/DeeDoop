//
//  DocumentDuplicateService.swift
//  DeeDoop
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Scans a folder for duplicate files (by size + creation date) and supports removing them.
final class DocumentDuplicateService: ObservableObject {
    
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var duplicateGroups: [FileDuplicateGroup] = []
    @Published private(set) var scanError: String?
    
    private var securityScopedURL: URL?
    
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
        
        await MainActor.run {
            duplicateGroups = groups
            isScanning = false
            scanProgress = 1
        }
    }
    
    /// Remove duplicates: keep file at keepIndex, delete the rest.
    func removeDuplicates(keepingFileAt keepIndex: Int, in group: FileDuplicateGroup) throws {
        let fileManager = FileManager.default
        for (index, url) in group.fileURLs.enumerated() where index != keepIndex {
            try fileManager.removeItem(at: url)
        }
        Task { @MainActor in
            duplicateGroups.removeAll { $0.id == group.id }
        }
    }
    
    /// Delete every file in the group (all copies). Removes the group from the list.
    func deleteAllInGroup(_ group: FileDuplicateGroup) throws {
        let fileManager = FileManager.default
        for url in group.fileURLs {
            try fileManager.removeItem(at: url)
        }
        Task { @MainActor in
            duplicateGroups.removeAll { $0.id == group.id }
        }
    }

    /// Remove all duplicate groups: keep the first file in each group.
    func removeAllDuplicatesKeepingFirst() throws {
        let groups = duplicateGroups
        let fileManager = FileManager.default
        for group in groups {
            for url in group.fileURLs.dropFirst() {
                try fileManager.removeItem(at: url)
            }
        }
        let idsToRemove = Set(groups.map(\.id))
        Task { @MainActor in
            duplicateGroups.removeAll { idsToRemove.contains($0.id) }
        }
    }
    
    /// Call when done with the selected folder (e.g. leaving the flow).
    func stopAccessingSecurityScopedResource() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}

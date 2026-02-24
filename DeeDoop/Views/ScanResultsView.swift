//
//  ScanResultsView.swift
//  DeeDoop
//

import Photos
import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var photoService: PhotoLibraryService
    
    private var hasAnyDuplicates: Bool {
        !photoService.photoDuplicateGroups.isEmpty || !photoService.videoDuplicateGroups.isEmpty
    }
    
    var body: some View {
        Group {
            if photoService.isScanning {
                ScanningView(progress: photoService.scanProgress)
            } else if !hasAnyDuplicates {
                NoDuplicatesView()
            } else {
                DuplicateGroupsListView(photoService: photoService)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.orange)
                .padding(.horizontal, 40)
            Text("Scanning your gallery…")
                .font(.headline)
            Text("Photos: size, date, dimensions, filename. Videos: size, date, duration, filename.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
}

struct NoDuplicatesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No duplicates found")
                .font(.title2.weight(.semibold))
            Text("Your selected date range has no duplicate photos or videos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DuplicateGroupsListView: View {
    @ObservedObject var photoService: PhotoLibraryService
    @State private var showRemoveAllConfirmation = false
    @State private var isRemovingAll = false
    @State private var removeAllError: String?
    
    var body: some View {
        List {
            Section {
                let total = photoService.photoDuplicateGroups.count + photoService.videoDuplicateGroups.count
                Text("\(total) duplicate groups found (photos and videos)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    showRemoveAllConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                        Text("Remove all duplicates (keep first in each group)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                }
                .disabled(isRemovingAll)
                
                if isRemovingAll {
                    HStack {
                        ProgressView()
                        Text("Removing…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = removeAllError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            if !photoService.photoDuplicateGroups.isEmpty {
                Section {
                    ForEach(photoService.photoDuplicateGroups) { group in
                        NavigationLink {
                            DuplicateGroupDetailView(group: group, photoService: photoService)
                        } label: {
                            DuplicateGroupRow(group: group)
                        }
                    }
                } header: {
                    Text("Photo duplicates")
                } footer: {
                    Text("\(photoService.photoDuplicateGroups.count) group(s)")
                }
            }
            
            if !photoService.videoDuplicateGroups.isEmpty {
                Section {
                    ForEach(photoService.videoDuplicateGroups) { group in
                        NavigationLink {
                            DuplicateGroupDetailView(group: group, photoService: photoService)
                        } label: {
                            DuplicateGroupRow(group: group)
                        }
                    }
                } header: {
                    Text("Video duplicates")
                } footer: {
                    Text("\(photoService.videoDuplicateGroups.count) group(s)")
                }
            }

            Section {
                Color.clear
                    .frame(height: 44)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                EmptyView()
            } footer: {
                EmptyView()
            }
            .listRowInsets(EdgeInsets())
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .alert("Remove all duplicates?", isPresented: $showRemoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) {
                Task { await removeAllDuplicates() }
            }
        } message: {
            Text("The first item in each group will be kept; all other duplicates will be deleted. This cannot be undone.")
        }
    }
    
    private func removeAllDuplicates() async {
        isRemovingAll = true
        removeAllError = nil
        do {
            try await photoService.removeAllDuplicatesKeepingFirst()
        } catch {
            removeAllError = error.localizedDescription
        }
        isRemovingAll = false
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    
    var body: some View {
        HStack(spacing: 12) {
            if let first = group.assets.first {
                AssetThumbnailView(asset: first, size: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.assets.count) duplicates")
                    .font(.headline)
                Text(group.displaySize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview("Scan results") {
    NavigationStack {
        ScanResultsView(photoService: PhotoLibraryService())
    }
}

#Preview("Scanning") {
    ScanningView(progress: 0.6)
}

#Preview("No duplicates") {
    NoDuplicatesView()
}

#Preview("Groups list") {
    DuplicateGroupsListView(photoService: PhotoLibraryService())
}

#Preview("Group row") {
    let fetch = PHAsset.fetchAssets(with: .image, options: nil)
    Group {
        if let asset = fetch.firstObject {
            let group = DuplicateGroup(
                id: "preview-row",
                assets: [asset, asset],
                fileSize: 2048,
                creationDate: Date(),
                mediaType: .image
            )
            List {
                DuplicateGroupRow(group: group)
            }
        } else {
            Text("Add photos to preview row")
        }
    }
}

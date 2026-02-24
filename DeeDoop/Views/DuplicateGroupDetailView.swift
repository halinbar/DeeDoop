//
//  DuplicateGroupDetailView.swift
//  DeeDoop
//

import Photos
import SwiftUI

struct DuplicateGroupDetailView: View {
    let group: DuplicateGroup
    @ObservedObject var photoService: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedKeepIndex: Int?
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteAllConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Group info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displaySize)
                            .font(.headline)
                        Text(group.displayDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                
                Text("Choose one to keep and remove the rest, or keep all.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                }
                
                // Asset grid
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 12),
                    GridItem(.adaptive(minimum: 100), spacing: 12),
                    GridItem(.adaptive(minimum: 100), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        AssetCardView(
                            asset: asset,
                            isSelected: selectedKeepIndex == index,
                            onSelect: { selectedKeepIndex = index }
                        )
                    }
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button {
                        Task { await removeDuplicates() }
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash")
                                Text("Remove duplicates (keep selected)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            selectedKeepIndex != nil && !isDeleting
                                ? Color.red
                                : Color.gray.opacity(0.3)
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(selectedKeepIndex == nil || isDeleting)
                    
                    Button {
                        showDeleteAllConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                            Text("Delete all \(group.assets.count) (remove entire group)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting)

                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Keep all (do nothing)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting)
                }
            }
            .padding()
        }
        .alert("Delete all \(group.assets.count)?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                Task { await deleteAllInGroup() }
            }
        } message: {
            Text("All \(group.assets.count) items in this group will be permanently deleted. This cannot be undone.")
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .all))
        .navigationTitle("\(group.assets.count) duplicates")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func removeDuplicates() async {
        guard let keepIndex = selectedKeepIndex else { return }
        errorMessage = nil
        isDeleting = true
        
        do {
            try await photoService.removeDuplicates(keepingAssetAt: keepIndex, in: group)
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }

    private func deleteAllInGroup() async {
        errorMessage = nil
        isDeleting = true
        do {
            try await photoService.deleteAllInGroup(group)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }
}

struct AssetCardView: View {
    let asset: PHAsset
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomTrailing) {
                AssetThumbnailView(asset: asset, size: 120)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 3)
                    )
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.orange))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let fetch = PHAsset.fetchAssets(with: .image, options: nil)
    let asset = fetch.firstObject
    return Group {
        if let asset = asset {
            let group = DuplicateGroup(
                id: "preview",
                assets: [asset, asset],
                fileSize: 1000,
                creationDate: Date(),
                mediaType: .image
            )
            NavigationStack {
                DuplicateGroupDetailView(group: group, photoService: PhotoLibraryService())
            }
        } else {
            Text("Add photos to library to preview")
                .padding()
        }
    }
}

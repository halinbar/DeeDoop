//
//  ScanResultsView.swift
//  DeeDoop
//

import Photos
import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var photoService: PhotoLibraryService
    let mediaFilter: PhotoLibraryService.MediaFilter
    
    private var hasAnyDuplicatesOrBursts: Bool {
        !photoService.photoDuplicateGroups.isEmpty
        || !photoService.videoDuplicateGroups.isEmpty
        || !photoService.photoBurstGroups.isEmpty
    }

    private var hasAnyVideoSizeItems: Bool {
        !photoService.videosBySizeItems.isEmpty
    }
    
    var body: some View {
        Group {
            if photoService.isScanning {
                ScanningView(progress: photoService.scanProgress)
            } else if !hasAnyDuplicatesOrBursts && !(mediaFilter == .videosOnly && hasAnyVideoSizeItems) {
                NoDuplicatesView()
            } else {
                if mediaFilter == .videosOnly {
                    VideoScanResultsContainer(photoService: photoService)
                } else {
                    DuplicateGroupsListView(photoService: photoService)
                }
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
            Text("Your selected date range has no duplicate photos, videos, or bursts.")
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
    @State private var isPhotoSectionExpanded = true
    @State private var isVideoSectionExpanded = true
    @State private var isBurstSectionExpanded = true
    
    var body: some View {
        List {
            Section {
                let duplicateTotal = photoService.photoDuplicateGroups.count + photoService.videoDuplicateGroups.count
                let burstTotal = photoService.photoBurstGroups.count
                Text("\(duplicateTotal) duplicate groups found (photos and videos)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if burstTotal > 0 {
                    Text("\(burstTotal) photo burst group(s) found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
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
                    if isPhotoSectionExpanded {
                        ForEach(photoService.photoDuplicateGroups) { group in
                            NavigationLink {
                                DuplicateGroupDetailView(group: group, photoService: photoService)
                            } label: {
                                DuplicateGroupRow(group: group)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Photo duplicates")
                        Spacer()
                        Image(systemName: isPhotoSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isPhotoSectionExpanded.toggle()
                        }
                    }
                } footer: {
                    Text("\(photoService.photoDuplicateGroups.count) group(s)")
                }
            }
            
            if !photoService.videoDuplicateGroups.isEmpty {
                Section {
                    if isVideoSectionExpanded {
                        ForEach(photoService.videoDuplicateGroups) { group in
                            NavigationLink {
                                DuplicateGroupDetailView(group: group, photoService: photoService)
                            } label: {
                                DuplicateGroupRow(group: group)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Video duplicates")
                        Spacer()
                        Image(systemName: isVideoSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isVideoSectionExpanded.toggle()
                        }
                    }
                } footer: {
                    Text("\(photoService.videoDuplicateGroups.count) group(s)")
                }
            }

            if !photoService.photoBurstGroups.isEmpty {
                Section {
                    if isBurstSectionExpanded {
                        ForEach(photoService.photoBurstGroups) { group in
                            NavigationLink {
                                BurstGroupDetailView(group: group, photoService: photoService)
                            } label: {
                                DuplicateGroupRow(group: group)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Photo bursts")
                        Spacer()
                        Image(systemName: isBurstSectionExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isBurstSectionExpanded.toggle()
                        }
                    }
                } footer: {
                    Text("\(photoService.photoBurstGroups.count) group(s)")
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

struct VideoScanResultsContainer: View {
    @ObservedObject var photoService: PhotoLibraryService
    @State private var mode: Mode = .duplicates

    enum Mode {
        case duplicates
        case bySize
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                Text("Duplicates").tag(Mode.duplicates)
                Text("By size").tag(Mode.bySize)
            }
            .pickerStyle(.segmented)
            .padding()

            if mode == .duplicates {
                DuplicateGroupsListView(photoService: photoService)
            } else {
                VideoSizeListView(photoService: photoService)
            }
        }
    }
}

struct VideoSizeListView: View {
    @ObservedObject var photoService: PhotoLibraryService
    @State private var selectedIDs = Set<String>()
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("\(photoService.videosBySizeItems.count) video(s) in this date range")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await removeSelected() }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete selected videos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                }
                .disabled(selectedIDs.isEmpty || isDeleting)

                if isDeleting {
                    HStack {
                        ProgressView()
                        Text("Deleting…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(photoService.videosBySizeItems) { item in
                    VideoSizeRow(
                        item: item,
                        isSelected: selectedIDs.contains(item.id)
                    ) {
                        if selectedIDs.contains(item.id) {
                            selectedIDs.remove(item.id)
                        } else {
                            selectedIDs.insert(item.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func removeSelected() async {
        guard !selectedIDs.isEmpty else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try await photoService.deleteVideosBySizeItems(withIDs: selectedIDs)
            await MainActor.run {
                selectedIDs.removeAll()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        isDeleting = false
    }
}

struct VideoSizeRow: View {
    let item: PhotoLibraryService.VideoBySizeItem
    let isSelected: Bool
    let onToggleSelection: () -> Void

    private var durationText: String {
        let totalSeconds = Int(item.duration.rounded())
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private var dateText: String {
        guard let date = item.creationDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 12) {
                AssetThumbnailView(asset: item.asset, size: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.headline)
                    Text(durationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.orange : Color.secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct BurstGroupDetailView: View {
    let group: DuplicateGroup
    @ObservedObject var photoService: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKeepIndices = Set<Int>()
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var fullScreenIndex: Int?
    @State private var isShowingFullScreen = false
    @State private var showDeleteEntireBurstConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                Text("Select one or more photos to keep from this burst. All unselected photos will be deleted.")
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

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 12),
                    GridItem(.adaptive(minimum: 100), spacing: 12),
                    GridItem(.adaptive(minimum: 100), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                        Button {
                            if selectedKeepIndices.contains(index) {
                                selectedKeepIndices.remove(index)
                            } else {
                                selectedKeepIndices.insert(index)
                            }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                AssetThumbnailView(asset: asset, size: 120)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedKeepIndices.contains(index) ? Color.orange : Color.clear, lineWidth: 3)
                                    )

                                if selectedKeepIndices.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(Color.orange))
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                fullScreenIndex = index
                                isShowingFullScreen = true
                            }
                        )
                    }
                }

                Button {
                    Task { await removeBurstDuplicates() }
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash")
                            Text("Remove unselected photos in burst")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        !selectedKeepIndices.isEmpty && !isDeleting
                            ? Color.red
                            : Color.gray.opacity(0.3)
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedKeepIndices.isEmpty || isDeleting)

                Button {
                    showDeleteEntireBurstConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                        Text("Delete entire burst (\(group.assets.count) photos)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(isDeleting ? 0.4 : 0.9))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isDeleting)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .all))
        .navigationTitle("\(group.assets.count) burst photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingFullScreen) {
            if let fullScreenIndex,
               fullScreenIndex < group.assets.count {
                PhotoFullScreenViewer(
                    assets: group.assets,
                    initialIndex: fullScreenIndex
                ) {
                    isShowingFullScreen = false
                }
            }
        }
        .alert("Delete entire burst?", isPresented: $showDeleteEntireBurstConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all \(group.assets.count) photos", role: .destructive) {
                Task { await deleteEntireBurst() }
            }
        } message: {
            Text("All \(group.assets.count) photos in this burst will be permanently deleted. This cannot be undone.")
        }
    }

    private func deleteEntireBurst() async {
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

    private func removeBurstDuplicates() async {
        guard !selectedKeepIndices.isEmpty else { return }
        errorMessage = nil
        isDeleting = true

        do {
            try await photoService.removeDuplicates(keepingIndices: selectedKeepIndices, in: group)
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
}

struct PhotoFullScreenViewer: View {
    let assets: [PHAsset]
    let initialIndex: Int
    let onClose: () -> Void

    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    ZoomableAssetImageView(asset: asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onAppear {
                currentIndex = min(max(initialIndex, 0), max(assets.count - 1, 0))
            }

            VStack {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(16)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

struct ZoomableAssetImageView: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    let zoomGesture = MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, value)
                        }
                        .onEnded { value in
                            if value < 1.0 {
                                scale = 1.0
                            }
                        }

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                        .gesture(zoomGesture)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task {
                await loadFullImage(targetSize: geo.size)
            }
        }
    }

    private func loadFullImage(targetSize: CGSize) async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let scaledSize = CGSize(
            width: targetSize.width * UIScreen.main.scale,
            height: targetSize.height * UIScreen.main.scale
        )

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: scaledSize,
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            Task { @MainActor in
                self.image = img
            }
        }
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
        ScanResultsView(photoService: PhotoLibraryService(), mediaFilter: .photosOnly)
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

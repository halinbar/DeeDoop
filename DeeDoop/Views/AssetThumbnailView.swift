//
//  AssetThumbnailView.swift
//  DeeDoop
//

import Photos
import SwiftUI

struct AssetThumbnailView: View {
    let asset: PHAsset
    let size: CGFloat
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: asset.mediaType == .video ? "video" : "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: size * UIScreen.main.scale, height: size * UIScreen.main.scale)
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            Task { @MainActor in
                self.image = img
            }
        }
    }
}

#Preview("Thumbnail") {
    let fetch = PHAsset.fetchAssets(with: .image, options: nil)
    Group {
        if let asset = fetch.firstObject {
            AssetThumbnailView(asset: asset, size: 120)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay { Text("No photos").foregroundStyle(.secondary) }
                .frame(width: 120, height: 120)
        }
    }
}

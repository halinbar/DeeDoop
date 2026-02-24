//
//  DuplicateGroup.swift
//  DeeDoop
//

import Photos
import SwiftUI

struct DuplicateGroup: Identifiable {
    let id: String
    let assets: [PHAsset]
    let fileSize: Int64
    let creationDate: Date?
    /// .image for photo groups, .video for video groups.
    let mediaType: PHAssetMediaType
    
    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var displayDate: String {
        guard let date = creationDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var isVideo: Bool { mediaType == .video }
}

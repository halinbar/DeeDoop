//
//  AssetType.swift
//  DeeDoop
//

import SwiftUI

enum AssetType: String, CaseIterable, Identifiable {
    case photos = "Photos"
    case videos = "Videos"
    case files = "Files"
    case contacts = "Contacts"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .photos: return "photo.on.rectangle.angled"
        case .videos: return "video.fill"
        case .files: return "folder"
        case .contacts: return "person.2"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .photos, .videos, .files: return true
        case .contacts: return false
        }
    }
    
    var comingSoonLabel: String? {
        isAvailable ? nil : "Coming Soon"
    }
}

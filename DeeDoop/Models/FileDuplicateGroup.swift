//
//  FileDuplicateGroup.swift
//  DeeDoop
//

import Foundation
import SwiftUI

struct FileDuplicateGroup: Identifiable {
    let id: String
    let fileURLs: [URL]
    let fileSize: Int64
    let creationDate: Date?
    
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
}

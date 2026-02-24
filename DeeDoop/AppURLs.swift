//
//  AppURLs.swift
//  DeeDoop
//
//  Centralized app URLs. Uses UIKit only for openSettingsURLString (no SwiftUI equivalent).
//

import Foundation
import UIKit

extension URL {
    /// URL to open this app’s page in the system Settings app.
    static var appSettings: URL {
        URL(string: UIApplication.openSettingsURLString)!
    }
}

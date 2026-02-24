//
//  DeeDoopApp.swift
//  DeeDoop
//
//  SwiftUI app entry.
//

import SwiftUI
import UIKit

@main
struct DeeDoopApp: App {

    init() {
        // Compact, opaque navigation bar to match the app background.
        let navBar = UINavigationBar.appearance()
        navBar.prefersLargeTitles = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .systemBackground
        navBar.standardAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(DeletedItemsStore.shared)
        }
    }
}


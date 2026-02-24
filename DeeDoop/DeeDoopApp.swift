//
//  DeeDoopApp.swift
//  DeeDoop
//
//  Find duplicates on your iPhone — photos, videos, files, and contacts.
//

import SwiftUI
import UIKit

@main
struct DeeDoopApp: App {

    init() {
        // Force compact navigation bar (no large title) so the bar stays slim
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
                .background(Color(.systemBackground).ignoresSafeArea(edges: .all))
                .ignoresSafeArea(edges: .all)
                .onAppear {
                    for scene in UIApplication.shared.connectedScenes {
                        guard let windowScene = scene as? UIWindowScene else { continue }
                        for window in windowScene.windows {
                            window.backgroundColor = .systemBackground
                        }
                    }
                }
        }
    }
}

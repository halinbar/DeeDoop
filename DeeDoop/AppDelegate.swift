//
//  AppDelegate.swift
//  DeeDoop
//
//  UIKit app entry. We create the window and set FullScreenHostingViewController
//  as root so the app content fills the entire screen (zero safe area at root).
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        configureNavigationBarAppearance()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .systemBackground
        window?.rootViewController = FullScreenHostingViewController()
        window?.makeKeyAndVisible()
        return true
    }

    private func configureNavigationBarAppearance() {
        let navBar = UINavigationBar.appearance()
        navBar.prefersLargeTitles = false
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .systemBackground
        navBar.standardAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
    }
}

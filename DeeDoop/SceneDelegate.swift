//
//  SceneDelegate.swift
//  DeeDoop
//
//  Sets our full-screen hosting controller as the window root so the app fills the entire screen.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let win = UIWindow(windowScene: windowScene)
        win.rootViewController = FullScreenHostingViewController()
        win.backgroundColor = .systemBackground
        win.makeKeyAndVisible()
        window = win
    }
}

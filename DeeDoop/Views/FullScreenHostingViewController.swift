//
//  FullScreenHostingViewController.swift
//  DeeDoop
//
//  Root view controller that embeds SwiftUI in a view which reports zero safe area,
//  so the app content fills the entire window (no black bars).
//

import SwiftUI
import UIKit

/// A view that reports zero safe area insets so its subviews get the full bounds.
private final class ZeroSafeAreaView: UIView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

/// Hosts the SwiftUI root content in a full-screen container (zero safe area).
final class FullScreenHostingViewController: UIViewController {

    private let hosting: UIHostingController<RootSwiftUIView>

    init() {
        hosting = UIHostingController(rootView: RootSwiftUIView())
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = ZeroSafeAreaView()
        view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}

private struct RootSwiftUIView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)
            ContentView()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .ignoresSafeArea(edges: .all)
        }
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

/// SwiftUI wrapper so we can use FullScreenHostingViewController as the WindowGroup root.
struct FullScreenHostingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FullScreenHostingViewController {
        FullScreenHostingViewController()
    }

    func updateUIViewController(_ uiViewController: FullScreenHostingViewController, context: Context) {}
}

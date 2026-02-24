//
//  AppHeaderView.swift
//  DeeDoop
//

import SwiftUI

/// Logo, app name, and tagline shown on the home screen. Padding is configurable.
struct AppHeaderView: View {
    var topPadding: CGFloat = 24
    var bottomPadding: CGFloat = 32
    var spacing: CGFloat = 8
    var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark")
                .font(.system(size: iconSize))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("DeeDoop")
                .font(.largeTitle.bold())
            Text("Find duplicates on your iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }
}

#Preview {
    AppHeaderView()
}

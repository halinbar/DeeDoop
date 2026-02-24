//
//  ContentView.swift
//  DeeDoop
//

import SwiftUI

struct ContentView: View {
    private static let spacerMinLength: CGFloat = 24

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea(edges: .all)
                VStack(spacing: 0) {
                Spacer(minLength: Self.spacerMinLength)

                AppHeaderView()

                Spacer(minLength: Self.spacerMinLength)
                
                // Asset type selection
                VStack(spacing: 12) {
                    ForEach(AssetType.allCases) { type in
                        if type.isAvailable {
                            Group {
                                switch type {
                                case .photos:
                                    NavigationLink {
                                        PhotosFlowView(mediaFilter: .photosOnly)
                                    } label: {
                                        AssetTypeRowLabel(assetType: type, isSelected: false)
                                    }
                                case .videos:
                                    NavigationLink {
                                        PhotosFlowView(mediaFilter: .videosOnly)
                                    } label: {
                                        AssetTypeRowLabel(assetType: type, isSelected: false)
                                    }
                                case .files:
                                    NavigationLink {
                                        DocumentsFlowView()
                                    } label: {
                                        AssetTypeRowLabel(assetType: type, isSelected: false)
                                    }
                                case .contacts:
                                    EmptyView()
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            AssetTypeRowLabel(assetType: type, isSelected: false)
                                .opacity(0.7)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer(minLength: 24)
                
                // Use bottom space so it's not black/unused
                Text("Photos · Videos · Files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .all)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        }
    }
}

struct AssetTypeRowLabel: View {
    let assetType: AssetType
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: assetType.icon)
                .font(.title2)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.orange : Color.gray.opacity(0.2))
                )
            
            Text(assetType.rawValue)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            if let label = assetType.comingSoonLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
                )
        )
    }
}

#Preview("Home") {
    ContentView()
}

#Preview("Asset type row") {
    AssetTypeRowLabel(assetType: .photos, isSelected: false)
}

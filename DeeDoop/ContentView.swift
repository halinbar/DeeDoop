//
//  ContentView.swift
//  DeeDoop
//

import SwiftUI

struct ContentView: View {
    private static let spacerMinLength: CGFloat = 24
    @State private var showDeduplicateMenu = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea(edges: .all)
                VStack(spacing: 0) {
                    Spacer(minLength: Self.spacerMinLength)

                    AppHeaderView()

                    Spacer(minLength: Self.spacerMinLength)

                    VStack(spacing: 12) {
                        // Deduplicate
                        Button { showDeduplicateMenu = true } label: {
                            HomeRowLabel(
                                icon: "rectangle.on.rectangle.slash",
                                color: .purple,
                                title: "Deduplicate",
                                subtitle: "Find and remove duplicate photos, videos, files & contacts."
                            )
                        }
                        .buttonStyle(.plain)

                        // Create Album
                        NavigationLink {
                            AlbumCreationFlowView()
                        } label: {
                            HomeRowLabel(
                                icon: "photo.stack",
                                color: .orange,
                                title: "Create Album",
                                subtitle: "Review, curate, and build a photo album."
                            )
                        }
                        .buttonStyle(.plain)

                        // History / Restore
                        NavigationLink {
                            HistoryView()
                        } label: {
                            HomeRowLabel(
                                icon: "clock.arrow.circlepath",
                                color: .blue,
                                title: "History & Restore",
                                subtitle: "See items DeeDoop deleted."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)

                    Text("Photos · Videos · Files · Contacts")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .all)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .sheet(isPresented: $showDeduplicateMenu) {
                DeduplicateMenuSheet()
            }
        }
    }
}

// MARK: - Shared row label

private struct HomeRowLabel: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

// MARK: - Deduplicate menu sheet

private struct DeduplicateMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dedupeRow(
                        icon: "photo.on.rectangle.angled",
                        color: .orange,
                        title: "Photos",
                        subtitle: "Scan for duplicate or similar photos."
                    ) {
                        PhotosFlowView(mediaFilter: .photosOnly)
                    }
                    dedupeRow(
                        icon: "video.badge.plus",
                        color: .pink,
                        title: "Videos",
                        subtitle: "Find and clean up duplicate videos."
                    ) {
                        PhotosFlowView(mediaFilter: .videosOnly)
                    }
                    dedupeRow(
                        icon: "doc.on.doc",
                        color: .teal,
                        title: "Files",
                        subtitle: "Detect duplicate documents and files."
                    ) {
                        DocumentsFlowView()
                    }
                    dedupeRow(
                        icon: "person.2.crop.square.stack",
                        color: .indigo,
                        title: "Contacts",
                        subtitle: "Merge duplicate contacts."
                    ) {
                        ContactsFlowView()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Deduplicate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func dedupeRow<Destination: View>(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
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

//
//  ContactsFlowView.swift
//  DeeDoop
//

import SwiftUI
import Contacts

struct ContactsFlowView: View {
    @StateObject private var service = ContactDuplicateService()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)

            Group {
                switch service.authorizationStatus {
                case .notDetermined:
                    VStack(spacing: 16) {
                        Text("Contacts access")
                            .font(.title2.weight(.semibold))
                        Text("DeeDoop needs access to your contacts to find duplicate entries.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Grant access") {
                            service.requestAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                case .denied, .restricted:
                    VStack(spacing: 16) {
                        Text("Contacts access denied")
                            .font(.title2.weight(.semibold))
                        Text("Please enable contacts access in Settings → DeeDoop → Contacts to find duplicate contacts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Link("Open Settings", destination: URL.appSettings)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                case .authorized:
                    if service.isScanning {
                        VStack(spacing: 24) {
                            Spacer()
                            ProgressView(value: service.scanProgress)
                                .progressViewStyle(.linear)
                                .tint(.orange)
                                .padding(.horizontal, 40)
                            Text("Scanning your contacts…")
                                .font(.headline)
                            if let error = service.scanError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                        }
                    } else if service.duplicateGroups.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 56))
                                .foregroundStyle(.secondary)
                            Text("No duplicate contacts found")
                                .font(.title2.weight(.semibold))
                            Text("Tap Scan to check again after you edit contacts.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Scan for duplicates") {
                                Task {
                                    await service.scanForDuplicates()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    } else {
                        ContactDuplicateGroupsListView(service: service)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if service.authorizationStatus == .authorized && !service.isScanning && service.duplicateGroups.isEmpty {
                await service.scanForDuplicates()
            }
        }
    }
}

struct ContactDuplicateGroupsListView: View {
    @ObservedObject var service: ContactDuplicateService
    @State private var showRescan = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("\(service.duplicateGroups.count) duplicate contact group(s) found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(service.duplicateGroups) { group in
                    NavigationLink {
                        ContactDuplicateGroupDetailView(group: group, service: service)
                    } label: {
                        HStack {
                            Image(systemName: "person.2")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.displayName)
                                    .font(.headline)
                                Text("\(group.count) duplicates")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Button("Rescan") {
                Task {
                    await service.scanForDuplicates()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

struct ContactDuplicateGroupDetailView: View {
    let group: ContactDuplicateGroup
    @ObservedObject var service: ContactDuplicateService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKeepIndex: Int?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(group.displayName)
                    .font(.title2.weight(.semibold))

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                }

                ForEach(Array(group.contacts.enumerated()), id: \.offset) { index, contact in
                    Button {
                        selectedKeepIndex = index
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedKeepIndex == index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedKeepIndex == index ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CNContactFormatter.string(from: contact, style: .fullName) ?? "Unnamed")
                                    .font(.headline)
                                if !contact.phoneNumbers.isEmpty {
                                    Text(contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if !contact.emailAddresses.isEmpty {
                                    Text(contact.emailAddresses.map { $0.value as String }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedKeepIndex == index ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    removeDuplicates()
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash")
                            Text("Remove duplicates (keep selected)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        selectedKeepIndex != nil && !isDeleting
                            ? Color.red
                            : Color.gray.opacity(0.3)
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedKeepIndex == nil || isDeleting)
            }
            .padding()
        }
        .navigationTitle("\(group.count) contacts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func removeDuplicates() {
        guard let keepIndex = selectedKeepIndex else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try service.removeDuplicates(keepingContactAt: keepIndex, in: group)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}


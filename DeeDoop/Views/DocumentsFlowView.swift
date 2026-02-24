//
//  DocumentsFlowView.swift
//  DeeDoop
//

import SwiftUI
import UIKit

struct DocumentsFlowView: View {
    @StateObject private var docService = DocumentDuplicateService()
    @State private var showDocumentPicker = false
    @State private var hasSelectedFolder = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea(edges: .all)
            Group {
                if !hasSelectedFolder {
                    DocumentFolderStepView(
                        onSelectFolder: {
                            showDocumentPicker = true
                        }
                    )
                } else {
                    DocumentScanResultsView(docService: docService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            docService.stopAccessingSecurityScopedResource()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                hasSelectedFolder = true
                Task {
                    await docService.scanForDuplicates(in: url)
                }
            }
        }
    }
}

struct DocumentFolderStepView: View {
    let onSelectFolder: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Select a folder to scan for duplicate files. Duplicates are found by file size and creation date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button(action: onSelectFolder) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Select folder")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom)
                .frame(minHeight: geo.size.height)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentScanResultsView: View {
    @ObservedObject var docService: DocumentDuplicateService
    @State private var mode: Mode = .duplicates

    enum Mode { case duplicates, bySize }

    private var hasAnyResults: Bool {
        !docService.duplicateGroups.isEmpty || !docService.filesBySizeItems.isEmpty
    }

    var body: some View {
        Group {
            if docService.isScanning {
                DocumentScanningView(progress: docService.scanProgress)
            } else if !hasAnyResults {
                DocumentNoDuplicatesView()
            } else {
                VStack(spacing: 0) {
                    Picker("View", selection: $mode) {
                        Text("Duplicates").tag(Mode.duplicates)
                        Text("By size").tag(Mode.bySize)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    if mode == .duplicates {
                        DocumentDuplicateGroupsListView(docService: docService)
                    } else {
                        FileSizeListView(docService: docService)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentScanningView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.orange)
                .padding(.horizontal, 40)
            Text("Scanning folder…")
                .font(.headline)
            Text("Looking for duplicate files by size and creation date")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
}

struct DocumentNoDuplicatesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No duplicates found")
                .font(.title2.weight(.semibold))
            Text("The selected folder has no duplicate files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentDuplicateGroupsListView: View {
    @ObservedObject var docService: DocumentDuplicateService
    @State private var showRemoveAllConfirmation = false
    @State private var isRemovingAll = false
    @State private var removeAllError: String?
    @State private var isGroupsExpanded = true
    
    var body: some View {
        List {
            Section {
                Text("\(docService.duplicateGroups.count) duplicate groups found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    showRemoveAllConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                        Text("Remove all duplicates (keep first in each group)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                }
                .disabled(isRemovingAll)
                
                if isRemovingAll {
                    HStack {
                        ProgressView()
                        Text("Removing…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = removeAllError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !docService.duplicateGroups.isEmpty {
                Section {
                    if isGroupsExpanded {
                        ForEach(docService.duplicateGroups) { group in
                            NavigationLink {
                                FileDuplicateGroupDetailView(group: group, docService: docService)
                            } label: {
                                FileDuplicateGroupRow(group: group)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Duplicate groups")
                        Spacer()
                        Image(systemName: isGroupsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isGroupsExpanded.toggle()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .alert("Remove all duplicates?", isPresented: $showRemoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) {
                performRemoveAll()
            }
        } message: {
            Text("The first file in each group will be kept; all other duplicates will be deleted. This cannot be undone.")
        }
    }
    
    private func performRemoveAll() {
        isRemovingAll = true
        removeAllError = nil
        do {
            try docService.removeAllDuplicatesKeepingFirst()
        } catch {
            removeAllError = error.localizedDescription
        }
        isRemovingAll = false
    }
}

struct FileDuplicateGroupRow: View {
    let group: FileDuplicateGroup
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(group.fileURLs.count) duplicates")
                    .font(.headline)
                Text(group.displaySize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(group.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct FileDuplicateGroupDetailView: View {
    let group: FileDuplicateGroup
    @ObservedObject var docService: DocumentDuplicateService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedKeepIndex: Int?
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteAllConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displaySize)
                            .font(.headline)
                        Text(group.displayDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                
                Text("Choose one to keep and remove the rest, or keep all.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                }
                
                ForEach(Array(group.fileURLs.enumerated()), id: \.offset) { index, url in
                    Button {
                        selectedKeepIndex = index
                    } label: {
                        HStack {
                            Image(systemName: selectedKeepIndex == index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedKeepIndex == index ? .orange : .secondary)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
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
                
                VStack(spacing: 12) {
                    if let keepIndex = selectedKeepIndex {
                        Button {
                            let url = group.fileURLs[keepIndex]
                            UIPasteboard.general.string = url.lastPathComponent
                            errorMessage = "File name copied to clipboard."
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("Copy selected file name")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.12))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isDeleting)
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

                    Button {
                        showDeleteAllConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                            Text("Delete all \(group.fileURLs.count) (remove entire group)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.9))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting)
                    
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Keep all (do nothing)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting)
                }
            }
            .padding()
        }
        .alert("Delete all \(group.fileURLs.count)?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                deleteAllInGroup()
            }
        } message: {
            Text("All \(group.fileURLs.count) files in this group will be permanently deleted. This cannot be undone.")
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .all))
        .navigationTitle("\(group.fileURLs.count) duplicates")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func deleteAllInGroup() {
        errorMessage = nil
        isDeleting = true
        do {
            try docService.deleteAllInGroup(group)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
    
    private func removeDuplicates() {
        guard let keepIndex = selectedKeepIndex else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try docService.removeDuplicates(keepingFileAt: keepIndex, in: group)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}

struct FileSizeListView: View {
    @ObservedObject var docService: DocumentDuplicateService
    @State private var selectedIDs = Set<String>()
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("\(docService.filesBySizeItems.count) file(s) in this folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    performDeleteSelected()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Move selected to trash")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                }
                .disabled(selectedIDs.isEmpty || isDeleting)

                if isDeleting {
                    HStack {
                        ProgressView()
                        Text("Moving to trash…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(docService.filesBySizeItems) { item in
                    FileSizeRow(
                        item: item,
                        isSelected: selectedIDs.contains(item.id)
                    ) {
                        if selectedIDs.contains(item.id) {
                            selectedIDs.remove(item.id)
                        } else {
                            selectedIDs.insert(item.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func performDeleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        errorMessage = nil
        isDeleting = true
        do {
            try docService.deleteFilesBySizeItems(withIDs: selectedIDs)
            selectedIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}

struct FileSizeRow: View {
    let item: DocumentDuplicateService.FileBySizeItem
    let isSelected: Bool
    let onToggleSelection: () -> Void

    private var dateText: String {
        guard let date = item.creationDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onToggleSelection) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.orange : Color.secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Documents flow") {
    NavigationStack {
        DocumentsFlowView()
    }
}

#Preview("Folder step") {
    DocumentFolderStepView(onSelectFolder: {})
}

#Preview("Document scanning") {
    DocumentScanningView(progress: 0.4)
}

#Preview("Document no duplicates") {
    DocumentNoDuplicatesView()
}

#Preview("Document results list") {
    DocumentDuplicateGroupsListView(docService: DocumentDuplicateService())
}

#Preview("File group row") {
    let group = FileDuplicateGroup(
        id: "preview",
        fileURLs: [
            URL(fileURLWithPath: "/Documents/file1.pdf"),
            URL(fileURLWithPath: "/Documents/file2.pdf")
        ],
        fileSize: 1024,
        creationDate: Date()
    )
    List {
        FileDuplicateGroupRow(group: group)
    }
}

#Preview("File group detail") {
    let group = FileDuplicateGroup(
        id: "preview",
        fileURLs: [
            URL(fileURLWithPath: "/Documents/file1.pdf"),
            URL(fileURLWithPath: "/Documents/file2.pdf")
        ],
        fileSize: 1024,
        creationDate: Date()
    )
    NavigationStack {
        FileDuplicateGroupDetailView(group: group, docService: DocumentDuplicateService())
    }
}

#Preview("Document scan results") {
    DocumentScanResultsView(docService: DocumentDuplicateService())
}

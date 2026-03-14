//
//  ContactDuplicateService.swift
//  DeeDoop
//

import Foundation
import Contacts

final class ContactDuplicateService: ObservableObject {

    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var duplicateGroups: [ContactDuplicateGroup] = []
    @Published private(set) var scanError: String?

    private let store = CNContactStore()

    init() {
        updateAuthorizationStatus()
    }

    func requestAuthorization() {
        store.requestAccess(for: .contacts) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.updateAuthorizationStatus()
            }
        }
    }

    private func updateAuthorizationStatus() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .authorized:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .restricted:
            authorizationStatus = .restricted
        case .limited:
            authorizationStatus = .authorized
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    func scanForDuplicates() async {
        guard authorizationStatus == .authorized else {
            await MainActor.run {
                scanError = "Contacts access is not authorized."
            }
            return
        }

        await MainActor.run {
            isScanning = true
            scanProgress = 0
            scanError = nil
            duplicateGroups = []
        }

        var keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor
        ]
        // Ensure all properties needed by CNContactFormatter(.fullName) are fetched.
        keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))

        var allContacts: [CNContact] = []
        do {
            let request = CNContactFetchRequest(keysToFetch: keys)
            try store.enumerateContacts(with: request) { contact, _ in
                allContacts.append(contact)
            }
        } catch {
            await MainActor.run {
                scanError = "Failed to read contacts: \(error.localizedDescription)"
                isScanning = false
            }
            return
        }

        let total = max(allContacts.count, 1)

        struct Node {
            let index: Int
            let contact: CNContact
            let nameKey: String
            let details: Set<String>
        }

        var nodes: [Node] = []
        nodes.reserveCapacity(allContacts.count)

        for (idx, contact) in allContacts.enumerated() {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let nameKey = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            var detailTokens = Set<String>()
            for phone in contact.phoneNumbers {
                let raw = phone.value.stringValue
                let norm = Self.normalizePhone(raw)
                if !norm.isEmpty { detailTokens.insert("p:\(norm)") }
            }
            for email in contact.emailAddresses {
                let e = (email.value as String).lowercased()
                if !e.isEmpty { detailTokens.insert("e:\(e)") }
            }
            // Could add addresses/URLs similarly if needed.

            nodes.append(Node(index: idx, contact: contact, nameKey: nameKey, details: detailTokens))

            if idx % 50 == 0 || idx == total - 1 {
                await MainActor.run {
                    scanProgress = Double(idx + 1) / Double(total)
                }
            }
        }

        // Build adjacency list for duplicates graph.
        var adjacency: [Int: Set<Int>] = [:]

        func connect(_ a: Int, _ b: Int) {
            adjacency[a, default: []].insert(b)
            adjacency[b, default: []].insert(a)
        }

        // Rule 2: identical details (even if names differ)
        var detailBuckets: [String: [Node]] = [:]
        for node in nodes {
            let key = node.details.sorted().joined(separator: "|")
            detailBuckets[key, default: []].append(node)
        }
        for bucket in detailBuckets.values where bucket.count >= 2 && !bucket.first!.details.isEmpty {
            let indices = bucket.map(\.index)
            for i in 0..<indices.count {
                for j in (i+1)..<indices.count {
                    connect(indices[i], indices[j])
                }
            }
        }

        // Rule 1: same name, one details set is subset of the other
        var nameBuckets: [String: [Node]] = [:]
        for node in nodes {
            nameBuckets[node.nameKey, default: []].append(node)
        }
        for bucket in nameBuckets.values where bucket.count >= 2 {
            let arr = bucket
            for i in 0..<arr.count {
                for j in (i+1)..<arr.count {
                    let a = arr[i]
                    let b = arr[j]
                    if a.details.isEmpty || b.details.isEmpty { continue }
                    if a.details.isSubset(of: b.details) || b.details.isSubset(of: a.details) {
                        connect(a.index, b.index)
                    }
                }
            }
        }

        // Connected components -> groups
        var visited = Set<Int>()
        var groups: [ContactDuplicateGroup] = []

        for node in nodes {
            let idx = node.index
            if visited.contains(idx) { continue }
            guard adjacency[idx] != nil else { continue } // not in any duplicate edge

            var stack: [Int] = [idx]
            var component = Set<Int>()
            while let current = stack.popLast() {
                if component.contains(current) { continue }
                component.insert(current)
                if let ns = adjacency[current] {
                    for n in ns where !component.contains(n) {
                        stack.append(n)
                    }
                }
            }

            visited.formUnion(component)
            if component.count >= 2 {
                let contacts = component.sorted().map { nodes[$0].contact }
                let id = contacts.map(\.identifier).joined(separator: "|")
                groups.append(ContactDuplicateGroup(id: id, contacts: contacts))
            }
        }

        let finalGroups = groups.sorted { $0.count > $1.count }
        await MainActor.run {
            duplicateGroups = finalGroups
            isScanning = false
            scanProgress = 1
        }
    }

    // MARK: - Delete helpers

    func removeDuplicates(keepingContactAt keepIndex: Int, in group: ContactDuplicateGroup) throws {
        let contacts = group.contacts
        guard keepIndex < contacts.count else { return }

        let toDelete = contacts.enumerated().compactMap { idx, contact in
            idx == keepIndex ? nil : contact
        }
        guard !toDelete.isEmpty else { return }

        let request = CNSaveRequest()
        for c in toDelete {
            let mutable = c.mutableCopy() as! CNMutableContact
            request.delete(mutable)
        }
        try store.execute(request)
        // Once deletion succeeds, remove this group from the published duplicates list
        DispatchQueue.main.async {
            self.duplicateGroups.removeAll { $0.id == group.id }
        }
    }

    // MARK: - Normalization

    private static func normalizePhone(_ raw: String) -> String {
        // Keep digits only, then take last 7–10 digits so we ignore country codes/prefixes.
        let digits = raw.compactMap { $0.isNumber ? $0 : nil }
        guard !digits.isEmpty else { return "" }
        let s = String(digits)
        let maxLen = min(10, s.count)
        let end = s.index(s.endIndex, offsetBy: -maxLen)
        return String(s[end...])
    }
}


//
//  ContactDuplicateGroup.swift
//  DeeDoop
//

import Contacts

struct ContactDuplicateGroup: Identifiable {
    let id: String
    let contacts: [CNContact]

    var displayName: String {
        // Use first contact's name as display
        CNContactFormatter.string(from: contacts.first ?? CNContact(), style: .fullName) ?? "Unnamed"
    }

    var count: Int { contacts.count }
}


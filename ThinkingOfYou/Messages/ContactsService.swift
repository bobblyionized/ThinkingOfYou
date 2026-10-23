//  ContactsService.swift
//  ThinkingOfYou/Messages — thin, nonisolated wrapper over CNContactStore.
//  Fetching runs off the main thread.

import Contacts
import Foundation

enum ContactsAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    /// iOS 18+ "limited access": only the contacts the user picked.
    case limited
    case denied
    case restricted

    var canRead: Bool { self == .authorized || self == .limited }
}

enum ContactsService {
    static func currentAccess() -> ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .limited // .limited (iOS 18+) and anything newer
        }
    }

    /// Shows the system prompt the first time. Returns whether access is granted.
    static func requestAccess() async -> Bool {
        do {
            return try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// Every contact (unified), on a background thread.
    static func fetchAll() async throws -> [Person] {
        try await Task.detached(priority: .userInitiated) {
            try ContactsService.fetchAllSync()
        }.value
    }

    static var keysToFetch: [CNKeyDescriptor] {
        [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey,
        ] as [CNKeyDescriptor]
    }

    static func fetchAllSync() throws -> [Person] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .userDefault
        request.unifyResults = true
        var people: [Person] = []
        try store.enumerateContacts(with: request) { contact, _ in
            people.append(Person(contact: contact))
        }
        return people
    }
}

extension Person {
    init(contact: CNContact) {
        let phones = contact.phoneNumbers.map { labeled in
            ContactHandle(kind: .phone,
                          label: labeled.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "",
                          value: labeled.value.stringValue)
        }
        let emails = contact.emailAddresses.map { labeled in
            ContactHandle(kind: .email,
                          label: labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "",
                          value: labeled.value as String)
        }
        self.init(id: contact.identifier,
                  givenName: contact.givenName,
                  familyName: contact.familyName,
                  nickname: contact.nickname,
                  organization: contact.organizationName,
                  phones: phones.filter { !$0.address.isEmpty },
                  emails: emails.filter { !$0.value.isEmpty },
                  thumbnailData: contact.thumbnailImageData)
    }
}

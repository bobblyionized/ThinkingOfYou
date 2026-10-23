//  Person.swift
//  ThinkingOfYou/Messages — a contact as the app sees it, plus the actions
//  you can take with one. Pure value types (no Contacts import here).

import Foundation

/// One phone number or email address of a contact.
struct ContactHandle: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case phone
        case email
    }

    let kind: Kind
    /// Localized label such as "mobile" or "home" ("" when unlabeled).
    let label: String
    /// The number or address as stored in Contacts.
    let value: String

    var id: String { "\(kind.rawValue):\(value)" }

    /// The form used in sms:/tel:/facetime: URLs and the composer.
    var address: String {
        kind == .phone ? ContactActions.sanitizedPhone(value) : value
    }
}

struct Person: Identifiable, Hashable, Sendable {
    /// CNContact.identifier
    let id: String
    let givenName: String
    let familyName: String
    let nickname: String
    let organization: String
    let phones: [ContactHandle]
    let emails: [ContactHandle]
    /// Small JPEG/PNG from Contacts, or nil. Render with `UIImage(data:)`.
    let thumbnailData: Data?

    init(id: String,
         givenName: String = "",
         familyName: String = "",
         nickname: String = "",
         organization: String = "",
         phones: [ContactHandle] = [],
         emails: [ContactHandle] = [],
         thumbnailData: Data? = nil) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.phones = phones
        self.emails = emails
        self.thumbnailData = thumbnailData
    }

    /// "Ada Lovelace", else nickname, organization, first number/email, "No Name".
    var displayName: String {
        let full = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if !nickname.isEmpty { return nickname }
        if !organization.isEmpty { return organization }
        if let first = phones.first?.value ?? emails.first?.value { return first }
        return "No Name"
    }

    /// Short name for notifications and buttons ("Text Ada").
    var shortName: String {
        if !nickname.isEmpty { return nickname }
        if !givenName.isEmpty { return givenName }
        return displayName
    }

    /// Up to two letters for an avatar placeholder.
    var initials: String {
        let source = [givenName, familyName].filter { !$0.isEmpty }
        let letters: [Character]
        if source.isEmpty {
            letters = displayName.split(separator: " ").prefix(2).compactMap { $0.first }
        } else {
            letters = source.prefix(2).compactMap { $0.first }
        }
        let text = String(letters).uppercased()
        return text.isEmpty ? "?" : text
    }

    /// Phones first, then emails.
    var handles: [ContactHandle] { phones + emails }

    var primaryPhone: ContactHandle? { phones.first }

    /// Best recipient for Messages/FaceTime: first phone, else first email.
    var messageAddress: String? { (phones.first ?? emails.first)?.address }

    var canMessage: Bool { messageAddress != nil }
    var canCall: Bool { primaryPhone != nil }
    var canFaceTime: Bool { messageAddress != nil }

    /// Case- and diacritic-insensitive match on names, emails and phone digits.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let fields = [displayName, givenName, familyName, nickname, organization] + emails.map(\.value)
        for field in fields where field.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        let digits = q.filter(\.isNumber)
        if digits.count >= 3 {
            return phones.contains { $0.value.filter(\.isNumber).contains(digits) }
        }
        return false
    }
}

/// What a person row / detail can do.
enum PersonAction: String, CaseIterable, Identifiable, Sendable {
    /// In-app composer (MFMessageComposeViewController) with an optional body.
    case message
    /// Hand off to the Messages app (sms: URL).
    case openInMessages
    case call
    case faceTime
    case faceTimeAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .message: return "Message"
        case .openInMessages: return "Open in Messages"
        case .call: return "Call"
        case .faceTime: return "FaceTime"
        case .faceTimeAudio: return "FaceTime Audio"
        }
    }

    /// SF Symbol name.
    var systemImage: String {
        switch self {
        case .message: return "message.fill"
        case .openInMessages: return "arrow.up.forward.app"
        case .call: return "phone.fill"
        case .faceTime: return "video.fill"
        case .faceTimeAudio: return "phone.bubble.fill"
        }
    }
}

/// URL builders for the system apps. Pure and testable.
enum ContactActions {
    private static let queryAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Keeps digits, a leading "+", and "*" / "#" (for extensions).
    static func sanitizedPhone(_ raw: String) -> String {
        var out = ""
        for ch in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isASCII, ch.isNumber {
                out.append(ch)
            } else if ch == "+", out.isEmpty {
                out.append(ch)
            } else if ch == "*" || ch == "#" {
                out.append(ch)
            }
        }
        return out
    }

    static func percentEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
    }

    /// sms:<address>&body=<text>  (iOS form), or sms:/open?addresses=a,b&body=
    /// for several recipients.
    static func smsURL(addresses: [String], body: String? = nil) -> URL? {
        let cleaned = addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let encodedBody = body.flatMap { $0.isEmpty ? nil : percentEncoded($0) }
        var text: String
        if cleaned.count > 1 {
            text = "sms:/open?addresses=" + cleaned.map(percentEncoded).joined(separator: ",")
            if let encodedBody { text += "&body=" + encodedBody }
        } else {
            text = "sms:" + (cleaned.first.map(percentEncodedAddress) ?? "")
            if let encodedBody { text += "&body=" + encodedBody }
        }
        return URL(string: text)
    }

    static func telURL(_ phone: String) -> URL? {
        let number = sanitizedPhone(phone)
        guard !number.isEmpty else { return nil }
        return URL(string: "tel:" + number.replacingOccurrences(of: "#", with: "%23"))
    }

    static func faceTimeURL(_ address: String) -> URL? {
        let target = percentEncodedAddress(address)
        return target.isEmpty ? nil : URL(string: "facetime:" + target)
    }

    static func faceTimeAudioURL(_ address: String) -> URL? {
        let target = percentEncodedAddress(address)
        return target.isEmpty ? nil : URL(string: "facetime-audio:" + target)
    }

    /// Phone numbers keep "+"; emails keep "@".
    private static func percentEncodedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") {
            let allowed = queryAllowed.union(CharacterSet(charactersIn: "@+"))
            return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        return sanitizedPhone(trimmed).replacingOccurrences(of: "#", with: "%23")
    }

    /// The system URL for a URL-based action (`.message` returns the sms: URL
    /// used as a fallback when the in-app composer is unavailable).
    static func url(for action: PersonAction, person: Person, body: String? = nil) -> URL? {
        switch action {
        case .message, .openInMessages:
            guard let address = person.messageAddress else { return nil }
            return smsURL(addresses: [address], body: body)
        case .call:
            guard let phone = person.primaryPhone?.value else { return nil }
            return telURL(phone)
        case .faceTime:
            guard let address = person.messageAddress else { return nil }
            return faceTimeURL(address)
        case .faceTimeAudio:
            guard let address = person.messageAddress else { return nil }
            return faceTimeAudioURL(address)
        }
    }
}

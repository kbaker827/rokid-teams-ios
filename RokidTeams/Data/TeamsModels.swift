import Foundation

// MARK: - Message

struct TeamsMessage: Identifiable, Equatable {
    let id: String
    let chatId: String
    let channelId: String?
    let teamId: String?
    let fromName: String
    let fromEmail: String?
    let body: String
    let createdDateTime: Date
    let importance: MessageImportance
    let chatType: ChatType
    let mentionsMe: Bool

    var ageFormatted: String {
        let diff = Date().timeIntervalSince(createdDateTime)
        if diff < 60        { return "just now" }
        if diff < 3600      { return "\(Int(diff/60))m ago" }
        if diff < 86400     { return "\(Int(diff/3600))h ago" }
        return createdDateTime.formatted(date: .abbreviated, time: .omitted)
    }

    var compactLine: String {
        let icon = chatType.icon
        let mention = mentionsMe ? " @me" : ""
        let truncated = body.count > 80 ? String(body.prefix(80)) + "…" : body
        return "\(icon) \(fromName)\(mention): \(truncated)"
    }
}

enum MessageImportance: String {
    case normal, high, urgent
}

enum ChatType: String {
    case oneOnOne   = "oneOnOne"
    case group      = "group"
    case meeting    = "meeting"
    case channel    = "channel"
    case unknown    = "unknown"

    var icon: String {
        switch self {
        case .oneOnOne: return "💬"
        case .group:    return "👥"
        case .meeting:  return "🎥"
        case .channel:  return "📢"
        case .unknown:  return "💭"
        }
    }

    var displayName: String {
        switch self {
        case .oneOnOne: return "Direct Message"
        case .group:    return "Group Chat"
        case .meeting:  return "Meeting Chat"
        case .channel:  return "Channel"
        case .unknown:  return "Chat"
        }
    }
}

// MARK: - Chat

struct TeamsChat: Identifiable, Equatable {
    let id: String
    let displayName: String
    let chatType: ChatType
    var lastMessage: TeamsMessage?
    var unreadCount: Int
    let members: [String]  // display names

    var title: String {
        if !displayName.isEmpty { return displayName }
        return members.prefix(3).joined(separator: ", ")
    }
}

// MARK: - Channel

struct TeamsChannel: Identifiable, Equatable {
    let id: String
    let teamId: String
    let teamName: String
    let displayName: String
    var lastMessage: TeamsMessage?
}

// MARK: - Meeting / Calendar Event

struct TeamsMeeting: Identifiable, Equatable {
    let id: String
    let subject: String
    let start: Date
    let end: Date
    let joinURL: String?
    let isOnlineMeeting: Bool
    let organizer: String?
    let attendeeCount: Int

    var isNow: Bool { Date() >= start && Date() <= end }
    var isUpcoming: Bool { start > Date() && start.timeIntervalSinceNow < 3600 }

    var timeFormatted: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    var minutesUntilStart: Int {
        max(0, Int(start.timeIntervalSinceNow / 60))
    }

    var statusIcon: String {
        if isNow      { return "🟢" }
        if isUpcoming { return "🟡" }
        return "📅"
    }
}

// MARK: - Presence

struct UserPresence: Identifiable, Equatable {
    let id: String       // userId
    let displayName: String
    let availability: PresenceAvailability
    let activity: String

    var statusLine: String { "\(availability.icon) \(displayName) · \(activity)" }
}

enum PresenceAvailability: String, CaseIterable {
    case available      = "Available"
    case busy           = "Busy"
    case doNotDisturb   = "DoNotDisturb"
    case beRightBack    = "BeRightBack"
    case away           = "Away"
    case offline        = "Offline"
    case unknown        = "Unknown"

    var icon: String {
        switch self {
        case .available:    return "🟢"
        case .busy:         return "🔴"
        case .doNotDisturb: return "⛔"
        case .beRightBack:  return "🟡"
        case .away:         return "🟠"
        case .offline:      return "⚫"
        case .unknown:      return "⚪"
        }
    }

    static func from(_ raw: String) -> PresenceAvailability {
        return allCases.first { $0.rawValue.lowercased() == raw.lowercased() } ?? .unknown
    }
}

// MARK: - Me (signed-in user)

struct TeamsUser: Equatable {
    let id: String
    let displayName: String
    let email: String
    let jobTitle: String?
}

// MARK: - Glasses display format

enum GlassesFormat: String, CaseIterable, Identifiable {
    case compact  = "compact"
    case detailed = "detailed"
    case minimal  = "minimal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:  return "Compact"
        case .detailed: return "Detailed"
        case .minimal:  return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .compact:  return "Unread count + latest message + next meeting"
        case .detailed: return "Full message text + meeting details"
        case .minimal:  return "Unread count only"
        }
    }
}

// MARK: - Glasses wire packets

struct GlassesPacket {
    static func make(type: String, text: String) -> Data {
        let dict: [String: String] = ["type": type, "text": text]
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return data + Data([0x0A])
    }

    static func parseQuery(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.uppercased().hasPrefix("QUERY:") {
            let q = trimmed.dropFirst("QUERY:".count).trimmingCharacters(in: .whitespaces)
            return q.isEmpty ? nil : q
        }
        return trimmed
    }
}

// MARK: - App state

enum AppAuthState {
    case signedOut
    case signingIn
    case signedIn(TeamsUser)
}

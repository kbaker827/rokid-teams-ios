import Foundation

actor TeamsAPIClient {

    private let base = URL(string: "https://graph.microsoft.com/v1.0")!

    // MARK: - Me

    func fetchMe(token: String) async throws -> TeamsUser {
        let json: [String: Any] = try await get("/me", token: token)
        guard let id   = json["id"]          as? String,
              let name = json["displayName"] as? String,
              let mail = json["mail"] as? String ?? (json["userPrincipalName"] as? String)
        else { throw GraphError.parseError("me") }
        return TeamsUser(
            id:           id,
            displayName:  name,
            email:        mail,
            jobTitle:     json["jobTitle"] as? String
        )
    }

    // MARK: - Chats

    func fetchChats(token: String) async throws -> [TeamsChat] {
        let json: [String: Any] = try await get(
            "/me/chats?$expand=lastMessagePreview,members&$top=20&$orderby=lastMessagePreview/createdDateTime desc",
            token: token
        )
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseChat($0) }
    }

    func fetchChatMessages(chatId: String, token: String, limit: Int = 10) async throws -> [TeamsMessage] {
        let encoded = chatId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chatId
        let json: [String: Any] = try await get(
            "/me/chats/\(encoded)/messages?$top=\(limit)&$orderby=createdDateTime desc",
            token: token
        )
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseMessage($0, chatId: chatId, chatType: .oneOnOne) }
    }

    // MARK: - My Presence

    func fetchMyPresence(token: String) async throws -> UserPresence {
        let json: [String: Any] = try await get("/me/presence", token: token)
        guard let id   = json["id"]           as? String,
              let avail = json["availability"] as? String
        else { throw GraphError.parseError("presence") }
        return UserPresence(
            id:           id,
            displayName:  "Me",
            availability: PresenceAvailability.from(avail),
            activity:     json["activity"] as? String ?? avail
        )
    }

    // MARK: - Presence for specific users

    func fetchPresence(userIds: [String], token: String) async throws -> [UserPresence] {
        guard !userIds.isEmpty else { return [] }
        let body: [String: Any] = ["ids": Array(userIds.prefix(650))]
        let json: [String: Any] = try await post("/communications/getPresencesByUserId", body: body, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { dict -> UserPresence? in
            guard let id    = dict["id"]           as? String,
                  let avail = dict["availability"] as? String else { return nil }
            return UserPresence(
                id:           id,
                displayName:  "",
                availability: PresenceAvailability.from(avail),
                activity:     dict["activity"] as? String ?? avail
            )
        }
    }

    // MARK: - Calendar / Meetings

    func fetchUpcomingMeetings(token: String) async throws -> [TeamsMeeting] {
        let now   = ISO8601DateFormatter().string(from: Date())
        let later = ISO8601DateFormatter().string(from: Date().addingTimeInterval(8 * 3600))
        let json: [String: Any] = try await get(
            "/me/calendarView?startDateTime=\(now)&endDateTime=\(later)&$top=10&$orderby=start/dateTime",
            token: token
        )
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseMeeting($0) }
    }

    // MARK: - Joined Teams (for channel access)

    func fetchJoinedTeams(token: String) async throws -> [(id: String, name: String)] {
        let json: [String: Any] = try await get("/me/joinedTeams", token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { dict -> (String, String)? in
            guard let id   = dict["id"]          as? String,
                  let name = dict["displayName"] as? String
            else { return nil }
            return (id, name)
        }
    }

    func fetchChannelMessages(teamId: String, channelId: String, token: String) async throws -> [TeamsMessage] {
        let json: [String: Any] = try await get(
            "/teams/\(teamId)/channels/\(channelId)/messages?$top=10",
            token: token
        )
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseMessage($0, chatId: channelId, chatType: .channel) }
    }

    // MARK: - HTTP helpers

    func get(_ path: String, token: String) async throws -> [String: Any] {
        let url = path.hasPrefix("http") ? URL(string: path)! : base.appendingPathComponent(path, conformingTo: .url)
        // Handle query strings properly
        let finalURL = path.contains("?") ? URL(string: base.absoluteString.dropLast() + path)! : url
        var req = URLRequest(url: finalURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        return try await execute(req)
    }

    func post(_ path: String, body: [String: Any], token: String) async throws -> [String: Any] {
        let url = base.appendingPathComponent(path, conformingTo: .url)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        return try await execute(req)
    }

    private func execute(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw GraphError.unauthorized }
            if http.statusCode == 403 { throw GraphError.forbidden }
            if http.statusCode == 404 { return [:] }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GraphError.httpError(http.statusCode, body)
            }
        }
        if data.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GraphError.parseError("JSON")
        }
        if let errObj = json["error"] as? [String: Any],
           let msg    = errObj["message"] as? String {
            throw GraphError.apiError(msg)
        }
        return json
    }

    // MARK: - Parsers

    private func parseChat(_ dict: [String: Any]) -> TeamsChat? {
        guard let id = dict["id"] as? String else { return nil }

        let chatTypeRaw = dict["chatType"] as? String ?? "unknown"
        let chatType    = ChatType(rawValue: chatTypeRaw) ?? .unknown

        let topic = dict["topic"] as? String ?? ""

        let members = (dict["members"] as? [[String: Any]])?.compactMap {
            $0["displayName"] as? String
        } ?? []

        var lastMessage: TeamsMessage? = nil
        if let preview = dict["lastMessagePreview"] as? [String: Any] {
            lastMessage = parseMessage(preview, chatId: id, chatType: chatType)
        }

        return TeamsChat(
            id:          id,
            displayName: topic,
            chatType:    chatType,
            lastMessage: lastMessage,
            unreadCount: 0,
            members:     members
        )
    }

    func parseMessage(_ dict: [String: Any], chatId: String, chatType: ChatType) -> TeamsMessage? {
        guard let id = dict["id"] as? String else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        func parseDate(_ key: String) -> Date {
            guard let s = dict[key] as? String else { return Date() }
            return iso.date(from: s) ?? iso2.date(from: s) ?? Date()
        }

        let bodyDict   = dict["body"] as? [String: Any]
        var bodyText   = bodyDict?["content"] as? String ?? ""
        // Strip HTML tags for clean display
        bodyText = bodyText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        bodyText = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bodyText.isEmpty else { return nil }

        let fromDict   = dict["from"]   as? [String: Any]
        let userDict   = fromDict?["user"] as? [String: Any]
        let fromName   = userDict?["displayName"] as? String ?? "Unknown"
        let fromEmail  = userDict?["email"] as? String

        let importanceRaw = dict["importance"] as? String ?? "normal"
        let importance    = MessageImportance(rawValue: importanceRaw) ?? .normal

        let mentions  = dict["mentions"] as? [[String: Any]] ?? []
        let mentionsMe = !mentions.isEmpty

        return TeamsMessage(
            id:              id,
            chatId:          chatId,
            channelId:       dict["channelIdentity"] != nil ? chatId : nil,
            teamId:          (dict["channelIdentity"] as? [String: Any])?["teamId"] as? String,
            fromName:        fromName,
            fromEmail:       fromEmail,
            body:            bodyText,
            createdDateTime: parseDate("createdDateTime"),
            importance:      importance,
            chatType:        chatType,
            mentionsMe:      mentionsMe
        )
    }

    private func parseMeeting(_ dict: [String: Any]) -> TeamsMeeting? {
        guard let id      = dict["id"]      as? String,
              let subject = dict["subject"] as? String
        else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        func parseDate(_ container: [String: Any]?, key: String) -> Date {
            guard let s = container?[key] as? String else { return Date() }
            return iso.date(from: s) ?? iso2.date(from: s) ?? Date()
        }

        let startDict = dict["start"] as? [String: Any]
        let endDict   = dict["end"]   as? [String: Any]
        let start     = parseDate(startDict, key: "dateTime")
        let end       = parseDate(endDict,   key: "dateTime")

        let isOnline  = dict["isOnlineMeeting"] as? Bool ?? false
        let joinURL   = (dict["onlineMeeting"] as? [String: Any])?["joinUrl"] as? String
                        ?? dict["onlineMeetingUrl"] as? String

        let organizer = ((dict["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any])?["name"] as? String
        let attendees = (dict["attendees"] as? [[String: Any]])?.count ?? 0

        return TeamsMeeting(
            id:              id,
            subject:         subject,
            start:           start,
            end:             end,
            joinURL:         joinURL,
            isOnlineMeeting: isOnline,
            organizer:       organizer,
            attendeeCount:   attendees
        )
    }
}

// MARK: - Errors

enum GraphError: LocalizedError {
    case unauthorized
    case forbidden
    case httpError(Int, String)
    case parseError(String)
    case apiError(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unauthorized:          return "Session expired. Please sign in again."
        case .forbidden:             return "Permission denied. Admin consent may be required for this scope."
        case .httpError(let c, _):   return "HTTP \(c) from Microsoft Graph."
        case .parseError(let w):     return "Could not parse \(w) from Graph response."
        case .apiError(let msg):     return "Graph API error: \(msg)"
        case .notConfigured:         return "Configure Client ID in Settings first."
        }
    }
}

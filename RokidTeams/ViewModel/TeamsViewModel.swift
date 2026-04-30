import Foundation
import Combine

@MainActor
final class TeamsViewModel: ObservableObject {

    // MARK: - Published state
    @Published var chats:         [TeamsChat]     = []
    @Published var meetings:      [TeamsMeeting]  = []
    @Published var myPresence:    UserPresence?   = nil
    @Published var currentUser:   TeamsUser?      = nil
    @Published var isLoading:     Bool            = false
    @Published var errorMessage:  String?         = nil
    @Published var lastRefresh:   Date?           = nil
    @Published var selectedTab:   Int             = 0

    // MARK: - Sub-objects
    let glassesServer = GlassesServer()
    let authManager:   TeamsAuthManager

    // MARK: - Private
    private let api      = TeamsAPIClient()
    private var pollTask: Task<Void, Never>?
    private var alertedMeetingIds: Set<String> = []
    private var prevMessageIds:    Set<String> = []

    var settings: SettingsStore

    // MARK: - Init

    init(settings: SettingsStore, authManager: TeamsAuthManager) {
        self.settings    = settings
        self.authManager = authManager

        glassesServer.onRemoteQuery = { [weak self] query in
            Task { @MainActor [weak self] in
                guard let self, self.settings.glassesQueryEnabled else { return }
                await self.handleGlassesQuery(query)
            }
        }
        glassesServer.start()
    }

    // MARK: - Auth helpers

    var isSignedIn: Bool {
        if case .signedIn = authManager.authState { return true }
        return settings.isLoggedIn
    }

    func signIn() async { await authManager.signIn() }
    func signOut() {
        authManager.signOut()
        chats = []; meetings = []; myPresence = nil; currentUser = nil
        stopPolling()
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(settings.pollInterval))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func refresh() async {
        guard settings.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await authManager.refreshIfNeeded()

            // Parallel fetch
            async let meTask       = api.fetchMe(token: token)
            async let chatsTask    = api.fetchChats(token: token)
            async let meetingsTask = api.fetchUpcomingMeetings(token: token)
            async let presenceTask = api.fetchMyPresence(token: token)

            let (me, fetchedChats, fetchedMeetings, presence) = try await (meTask, chatsTask, meetingsTask, presenceTask)

            // Update user
            currentUser = me
            if case .signingIn = authManager.authState {
                authManager.authState = .signedIn(me)
            }

            // Check for new messages
            checkNewMessages(fetchedChats)
            chats    = fetchedChats
            meetings = fetchedMeetings.sorted { $0.start < $1.start }
            myPresence = UserPresence(
                id:           presence.id,
                displayName:  me.displayName,
                availability: presence.availability,
                activity:     presence.activity
            )

            // Check meeting alerts
            checkMeetingAlerts()

            lastRefresh  = Date()
            errorMessage = nil

            // Push to glasses
            glassesServer.broadcastSummary(
                chats:    chats,
                meetings: meetings,
                presence: myPresence,
                format:   settings.glassesFormat
            )

        } catch GraphError.unauthorized {
            errorMessage = "Session expired. Please sign in again."
            authManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
            glassesServer.broadcastError(error.localizedDescription)
        }
    }

    // MARK: - Alerts

    private func checkNewMessages(_ newChats: [TeamsChat]) {
        guard !prevMessageIds.isEmpty else {
            // First load — seed IDs, don't alert
            let ids = newChats.compactMap { $0.lastMessage?.id }
            prevMessageIds = Set(ids)
            return
        }

        for chat in newChats {
            guard let msg = chat.lastMessage,
                  !prevMessageIds.contains(msg.id),
                  msg.createdDateTime > Date().addingTimeInterval(-Double(settings.pollInterval) * 2)
            else { continue }

            let shouldAlert: Bool
            switch chat.chatType {
            case .oneOnOne: shouldAlert = settings.alertDirectMessages
            default:        shouldAlert = settings.alertMentions && msg.mentionsMe
                                       || settings.alertUrgent   && msg.importance == .urgent
            }
            if shouldAlert { glassesServer.broadcastMessageAlert(msg) }
        }

        prevMessageIds = Set(newChats.compactMap { $0.lastMessage?.id })
    }

    private func checkMeetingAlerts() {
        guard settings.alertMeetingStart else { return }
        let threshold = TimeInterval(settings.meetingAlertMinutes * 60)

        for meeting in meetings {
            guard !alertedMeetingIds.contains(meeting.id),
                  meeting.start > Date(),
                  meeting.start.timeIntervalSinceNow <= threshold + 30
            else { continue }
            glassesServer.broadcastMeetingAlert(meeting)
            alertedMeetingIds.insert(meeting.id)
        }
        // Clean up past meetings
        let upcomingIds = Set(meetings.map { $0.id })
        alertedMeetingIds = alertedMeetingIds.intersection(upcomingIds)
    }

    // MARK: - Glasses query handler

    private func handleGlassesQuery(_ query: String) async {
        let lower = query.lowercased()
        guard settings.isLoggedIn else {
            glassesServer.broadcastError("Not signed in to Teams")
            return
        }

        // Messages
        if lower.contains("message") || lower.contains("chat") || lower.contains("dm") {
            let allMessages = chats.compactMap { $0.lastMessage }
                .sorted { $0.createdDateTime > $1.createdDateTime }
            glassesServer.broadcastMessages(allMessages)
            return
        }

        // Meetings / calendar
        if lower.contains("meeting") || lower.contains("calendar") || lower.contains("schedule") {
            glassesServer.broadcastMeetings(meetings)
            return
        }

        // Presence / status
        if lower.contains("presence") || lower.contains("status") || lower.contains("available") {
            if let p = myPresence {
                glassesServer.broadcastPresence(p)
            } else {
                glassesServer.broadcastStatus("Presence not loaded yet")
            }
            return
        }

        // Unread / summary
        if lower.contains("unread") || lower.contains("summary") || lower.contains("count") {
            glassesServer.broadcastSummary(
                chats:    chats,
                meetings: meetings,
                presence: myPresence,
                format:   settings.glassesFormat
            )
            return
        }

        // Next meeting
        if lower.contains("next") {
            if let next = meetings.filter({ $0.start > Date() }).sorted(by: { $0.start < $1.start }).first {
                glassesServer.broadcastMeetingAlert(next)
            } else {
                glassesServer.broadcastStatus("No upcoming meetings")
            }
            return
        }

        // Refresh
        if lower.contains("refresh") || lower.contains("reload") {
            await refresh()
            return
        }

        // Presence lookup for a specific person name
        // e.g. "QUERY: presence John"
        if lower.hasPrefix("presence ") {
            let name = String(query.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            glassesServer.broadcastStatus("🔍 Looking up \(name)…")
            // Try to find in chat members
            let match = chats.first { $0.title.localizedCaseInsensitiveContains(name) }
            if let chat = match, let msg = chat.lastMessage {
                glassesServer.broadcastStatus("\(chat.chatType.icon) \(chat.title): last active \(msg.ageFormatted)")
            } else {
                glassesServer.broadcastStatus("Could not find \(name) in recent chats")
            }
            return
        }

        // Default: push summary
        glassesServer.broadcastSummary(chats: chats, meetings: meetings, presence: myPresence, format: .compact)
    }

    // MARK: - Computed views

    var recentMessages: [TeamsMessage] {
        chats.compactMap { $0.lastMessage }
            .sorted { $0.createdDateTime > $1.createdDateTime }
    }

    var todaysMeetings: [TeamsMeeting] {
        let cal = Calendar.current
        return meetings.filter { cal.isDateInToday($0.start) }.sorted { $0.start < $1.start }
    }

    var nextMeeting: TeamsMeeting? {
        meetings.filter { $0.start > Date() }.sorted { $0.start < $1.start }.first
    }
}

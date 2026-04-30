import Foundation
import Network

/// Bidirectional TCP server on port 8098.
/// Glasses → Phone: "QUERY: messages" / "QUERY: meetings" / etc.
/// Phone → Glasses: newline-delimited JSON packets
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    var onRemoteQuery: ((String) -> Void)?

    private var listener:    NWListener?
    private var connections: [ConnectionWrapper] = []
    private let port: NWEndpoint.Port = 8098
    private let queue = DispatchQueue(label: "TeamsGlassesQ", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.isRunning = (state == .ready) }
        }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        clientCount = 0; isRunning = false
    }

    // MARK: - Broadcast helpers

    /// Push Teams HUD summary.
    func broadcastSummary(
        chats: [TeamsChat],
        meetings: [TeamsMeeting],
        presence: UserPresence?,
        format: GlassesFormat
    ) {
        let unread = chats.filter { ($0.lastMessage?.createdDateTime ?? Date.distantPast) > Date().addingTimeInterval(-300) }.count
        let nextMeeting = meetings.filter { $0.start > Date() }.sorted { $0.start < $1.start }.first

        let text: String
        switch format {
        case .minimal:
            text = "💬 \(unread) recent  \(presence?.availability.icon ?? "") \(presence?.activity ?? "")"

        case .compact:
            var lines: [String] = []
            if let p = presence {
                lines.append("\(p.availability.icon) \(p.activity)")
            }
            lines.append("💬 \(unread) recent messages")
            if let m = nextMeeting {
                let mins = m.minutesUntilStart
                lines.append("\(m.statusIcon) \(m.subject) in \(mins)m")
            }
            if let latest = chats.compactMap({ $0.lastMessage }).sorted(by: { $0.createdDateTime > $1.createdDateTime }).first {
                lines.append("\(latest.chatType.icon) \(latest.fromName): \(String(latest.body.prefix(60)))")
            }
            text = lines.joined(separator: "\n")

        case .detailed:
            var lines: [String] = []
            if let p = presence { lines.append("\(p.availability.icon) Status: \(p.activity)") }
            if let m = nextMeeting {
                lines.append("📅 Next: \(m.subject) @ \(m.timeFormatted)")
            }
            for chat in chats.prefix(3) {
                if let msg = chat.lastMessage {
                    lines.append("\(msg.chatType.icon) \(msg.fromName): \(String(msg.body.prefix(50)))")
                }
            }
            text = lines.joined(separator: "\n")
        }
        broadcast(type: "teams", text: text)
    }

    /// Alert glasses about a new message.
    func broadcastMessageAlert(_ msg: TeamsMessage) {
        let mention = msg.mentionsMe ? " @you" : ""
        let urgency = msg.importance == .urgent ? "🚨 URGENT" : "💬 NEW"
        broadcast(type: "alert", text: "\(urgency)\(mention)\n\(msg.chatType.icon) \(msg.fromName): \(String(msg.body.prefix(80)))")
    }

    /// Alert glasses about an upcoming meeting.
    func broadcastMeetingAlert(_ meeting: TeamsMeeting) {
        let mins = meeting.minutesUntilStart
        let when = mins == 0 ? "NOW" : "in \(mins) min"
        broadcast(type: "meeting", text: "📅 Starting \(when): \(meeting.subject)\n\(meeting.timeFormatted)")
    }

    /// Push detailed message list.
    func broadcastMessages(_ messages: [TeamsMessage]) {
        if messages.isEmpty {
            broadcast(type: "messages", text: "No recent messages")
            return
        }
        let lines = messages.prefix(5).map { "\($0.chatType.icon) \($0.fromName) (\($0.ageFormatted)): \(String($0.body.prefix(60)))" }
        broadcast(type: "messages", text: lines.joined(separator: "\n"))
    }

    /// Push meeting list.
    func broadcastMeetings(_ meetings: [TeamsMeeting]) {
        if meetings.isEmpty {
            broadcast(type: "meetings", text: "No upcoming meetings today")
            return
        }
        let lines = meetings.prefix(4).map { "\($0.statusIcon) \($0.subject)\n  \($0.timeFormatted)" }
        broadcast(type: "meetings", text: lines.joined(separator: "\n"))
    }

    func broadcastPresence(_ presence: UserPresence) {
        broadcast(type: "presence", text: presence.statusLine)
    }

    func broadcastStatus(_ text: String) { broadcast(type: "status",  text: text) }
    func broadcastError (_ text: String) { broadcast(type: "error",   text: "❌ \(text)") }

    // MARK: - Private

    private func accept(_ nwConn: NWConnection) {
        let w = ConnectionWrapper(connection: nwConn, queue: queue)
        w.onReceiveLine = { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                if let q = GlassesPacket.parseQuery(from: line) { self.onRemoteQuery?(q) }
            }
        }
        w.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connections.removeAll { $0 === w }
                self?.clientCount = self?.connections.count ?? 0
            }
        }
        connections.append(w)
        clientCount = connections.count
        w.start()
    }

    private func broadcast(type: String, text: String) {
        let packet = GlassesPacket.make(type: type, text: text)
        connections.forEach { $0.send(packet) }
    }
}

// MARK: - Connection wrapper

private final class ConnectionWrapper {
    let connection: NWConnection
    var onReceiveLine: ((String) -> Void)?
    var onDisconnect:  (() -> Void)?
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection; self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed   = state { self?.onDisconnect?() }
            if case .cancelled = state { self?.onDisconnect?() }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func send(_ data: Data) { connection.send(content: data, completion: .contentProcessed { _ in }) }
    func cancel() { connection.cancel() }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
            guard let self else { return }
            if let d = data, !d.isEmpty { self.buffer.append(d); self.flush() }
            if done || err != nil { self.onDisconnect?() } else { self.receiveNext() }
        }
    }

    private func flush() {
        while let idx = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: line, encoding: .utf8) { onReceiveLine?(s) }
        }
    }
}

import SwiftUI

struct GlassesPreviewView: View {
    @EnvironmentObject private var vm: TeamsViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    glassesMockup
                    commandCard
                    packetCard
                    connectionCard
                }
                .padding()
            }
            .navigationTitle("Glasses Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Glasses mockup

    private var glassesMockup: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(16/4, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(previewLines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(red: 0.3, green: 0.6, blue: 1.0))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .padding(.horizontal)
            Text("Rokid AR Glasses · TCP :8098")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var previewLines: [String] {
        guard vm.isSignedIn else { return ["Sign in to Microsoft Teams…"] }
        if vm.chats.isEmpty && vm.meetings.isEmpty { return ["Loading Teams data…"] }

        var lines: [String] = []
        if let p = vm.myPresence { lines.append("\(p.availability.icon) \(p.activity)") }
        let recent = vm.recentMessages.count
        lines.append("💬 \(recent) recent messages")
        if let m = vm.nextMeeting {
            lines.append("\(m.statusIcon) \(m.subject) @ \(m.timeFormatted)")
        }
        if let latest = vm.recentMessages.first {
            lines.append("\(latest.chatType.icon) \(latest.fromName): \(String(latest.body.prefix(50)))")
        }
        return lines
    }

    // MARK: - Command card

    private var commandCard: some View {
        GroupBox("Glasses → Phone Commands") {
            VStack(alignment: .leading, spacing: 8) {
                commandRow(cmd: "QUERY: messages",      desc: "Show recent messages")
                commandRow(cmd: "QUERY: meetings",      desc: "Show today's meetings")
                commandRow(cmd: "QUERY: next",          desc: "Show the next upcoming meeting")
                commandRow(cmd: "QUERY: status",        desc: "Show your presence / status")
                commandRow(cmd: "QUERY: unread",        desc: "Push current summary")
                commandRow(cmd: "QUERY: presence John", desc: "Look up John's last activity")
                commandRow(cmd: "QUERY: refresh",       desc: "Reload from Microsoft Graph")

                Divider().padding(.vertical, 4)
                Text("Plain text sends the default summary.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func commandRow(cmd: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cmd)
                .font(.system(.caption2, design: .monospaced))
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            Text(desc).font(.caption2).foregroundStyle(.secondary).padding(.leading, 6)
        }
    }

    // MARK: - Packet types card

    private var packetCard: some View {
        GroupBox("Phone → Glasses Packet Types") {
            VStack(alignment: .leading, spacing: 6) {
                packetRow(type: "teams",    example: "🟢 Available\n💬 3 recent  📅 Standup @ 2:00 PM")
                packetRow(type: "alert",    example: "💬 NEW @you\n💬 Sarah: Hey, quick question…")
                packetRow(type: "meeting",  example: "📅 Starting in 5 min: Weekly Standup\n2:00 PM – 2:30 PM")
                packetRow(type: "messages", example: "💬 Sarah (2m): Can you review the PR?")
                packetRow(type: "meetings", example: "🟡 Standup @ 2:00–2:30 PM\n📅 Review @ 4:00–5:00 PM")
                packetRow(type: "presence", example: "🔴 John Smith · In a meeting")
                packetRow(type: "status",   example: "🔍 Looking up John…")
                packetRow(type: "error",    example: "❌ Session expired")
            }
        }
    }

    private func packetRow(type: String, example: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("{\"type\":\"\(type)\",\"text\":\"...\"}")
                .font(.system(.caption2, design: .monospaced))
            Text(example).font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Connection card

    private var connectionCard: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("TCP Server", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text(vm.glassesServer.isRunning ? "Running" : "Stopped")
                        .foregroundStyle(vm.glassesServer.isRunning ? .green : .red)
                        .font(.subheadline.weight(.medium))
                }
                HStack {
                    Label("Port",    systemImage: "network")
                    Spacer()
                    Text("8098").foregroundStyle(.secondary)
                }
                HStack {
                    Label("Clients", systemImage: "display.2")
                    Spacer()
                    Text("\(vm.glassesServer.clientCount)").foregroundStyle(.secondary)
                }
                HStack {
                    Label("Account", systemImage: "person.fill")
                    Spacer()
                    Text(vm.currentUser?.email ?? "Not signed in").foregroundStyle(.secondary)
                }
                if let r = vm.lastRefresh {
                    HStack {
                        Label("Last refresh", systemImage: "clock")
                        Spacer()
                        Text(r.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}

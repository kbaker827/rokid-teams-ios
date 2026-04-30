import SwiftUI

struct TeamsHomeView: View {
    @EnvironmentObject private var vm: TeamsViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Group {
                if !vm.isSignedIn {
                    signInView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Microsoft Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    serverDot
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
        }
    }

    // MARK: - Sign in

    private var signInView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Rokid Teams HUD")
                    .font(.title.weight(.bold))
                Text("See your Teams messages and meetings on your Rokid AR glasses in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if settings.clientId.isEmpty {
                VStack(spacing: 6) {
                    Label("Add your Azure App Client ID in Settings first", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("Register a free app at portal.azure.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            Button {
                Task { await vm.signIn() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign in with Microsoft")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(settings.clientId.isEmpty)

            if case .signingIn = vm.authManager.authState {
                ProgressView("Signing in…")
            }

            Spacer()
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        List {
            // Presence
            if let p = vm.myPresence {
                Section {
                    HStack {
                        Text(p.availability.icon).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.currentUser?.displayName ?? "My Status")
                                .font(.subheadline.weight(.medium))
                            Text(p.activity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(p.availability.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Next meeting
            if let meeting = vm.nextMeeting {
                Section("Next Meeting") {
                    MeetingRow(meeting: meeting)
                }
            }

            // Today's meetings
            if vm.todaysMeetings.count > 1 {
                Section("Today's Schedule") {
                    ForEach(vm.todaysMeetings) { meeting in
                        MeetingRow(meeting: meeting)
                    }
                }
            }

            // Recent messages
            Section("Recent Messages") {
                if vm.recentMessages.isEmpty {
                    Text("No recent messages")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(vm.recentMessages.prefix(15)) { msg in
                        MessageRow(message: msg)
                    }
                }
            }

            // Last refresh
            if let r = vm.lastRefresh {
                Section {
                    Text("Updated \(r.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
        }
        .refreshable { await vm.refresh() }
    }

    // MARK: - Toolbar

    private var serverDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(vm.glassesServer.isRunning ? .green : .red)
                .frame(width: 8, height: 8)
            Text(":8098")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await vm.refresh() }
        } label: {
            if vm.isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(vm.isLoading || !vm.isSignedIn)
    }
}

// MARK: - Meeting row

struct MeetingRow: View {
    let meeting: TeamsMeeting

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(meeting.statusIcon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.subject)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(meeting.timeFormatted)
                        .font(.caption)
                    if meeting.isOnlineMeeting {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.secondary)
                if let org = meeting.organizer {
                    Text(org)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if meeting.isNow {
                Text("NOW")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
            } else if meeting.isUpcoming {
                Text("\(meeting.minutesUntilStart)m")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.yellow.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Message row

struct MessageRow: View {
    let message: TeamsMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: message.fromName).opacity(0.2))
                    .frame(width: 36, height: 36)
                Text(String(message.fromName.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(avatarColor(for: message.fromName))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.fromName)
                        .font(.subheadline.weight(.medium))
                    if message.mentionsMe {
                        Text("@you")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if message.importance == .urgent {
                        Image(systemName: "exclamationmark.2")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Text(message.ageFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(message.chatType.displayName, systemImage: "bubble.left")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .red, .teal, .indigo]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}

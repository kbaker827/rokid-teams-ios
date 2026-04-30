import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: TeamsViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Account
                Section("Microsoft Account") {
                    if vm.isSignedIn {
                        if let user = vm.currentUser {
                            LabeledContent("Signed in as", value: user.displayName)
                            LabeledContent("Email", value: user.email)
                        }
                        Button("Sign Out", role: .destructive) { vm.signOut() }
                    } else {
                        Button("Sign in with Microsoft") {
                            Task { await vm.signIn() }
                        }
                        .disabled(settings.clientId.isEmpty)
                    }
                }

                // MARK: Azure App Registration
                Section {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $settings.clientId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                    TextField("common  (or your tenant ID)", text: $settings.tenantId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Azure App Registration")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Register a free app at portal.azure.com")
                        Text("2. Add redirect URI: \(SettingsStore.redirectURI)")
                        Text("3. Add Mobile/Desktop platform")
                        Text("4. Grant: User.Read, Chat.Read, Presence.Read, Calendars.Read")
                        Link("Azure Portal →", destination: URL(string: "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // MARK: Polling
                Section("Polling") {
                    HStack {
                        Text("Refresh every")
                        Spacer()
                        Text("\(settings.pollInterval)s").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.pollInterval) },
                        set: { settings.pollInterval = Int($0) }
                    ), in: 15...300, step: 15) {
                        Text("Interval")
                    } minimumValueLabel: { Text("15s").font(.caption) }
                      maximumValueLabel: { Text("5m").font(.caption)  }
                }

                // MARK: Alerts
                Section("Glasses Alerts") {
                    Toggle("New direct messages",  isOn: $settings.alertDirectMessages)
                    Toggle("@mentions in channels", isOn: $settings.alertMentions)
                    Toggle("Urgent messages",       isOn: $settings.alertUrgent)
                    Toggle("Meeting starting soon", isOn: $settings.alertMeetingStart)
                    if settings.alertMeetingStart {
                        HStack {
                            Text("Alert before meeting")
                            Spacer()
                            Text("\(settings.meetingAlertMinutes) min").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.meetingAlertMinutes) },
                            set: { settings.meetingAlertMinutes = Int($0) }
                        ), in: 1...30, step: 1)
                    }
                }

                // MARK: Glasses
                Section("Glasses Integration") {
                    Toggle("Accept queries from glasses", isOn: $settings.glassesQueryEnabled)
                    Picker("Display format", selection: $settings.glassesFormat) {
                        ForEach(GlassesFormat.allCases) { fmt in
                            VStack(alignment: .leading) {
                                Text(fmt.displayName)
                                Text(fmt.description).font(.caption).foregroundStyle(.secondary)
                            }.tag(fmt)
                        }
                    }
                    LabeledContent("TCP port", value: "8098").foregroundStyle(.secondary)
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App",     value: "Rokid Teams HUD")
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("API",     value: "Microsoft Graph v1.0")
                    Link("Microsoft Graph docs",
                         destination: URL(string: "https://learn.microsoft.com/en-us/graph/overview")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

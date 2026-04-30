import Foundation
import Combine

final class SettingsStore: ObservableObject {

    // MARK: - Azure App Registration
    /// Client ID from Azure App Registration
    @Published var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: "teams_client_id") }
    }
    /// Tenant ID — use "common" for multi-tenant / personal accounts
    @Published var tenantId: String {
        didSet { UserDefaults.standard.set(tenantId, forKey: "teams_tenant_id") }
    }

    // MARK: - OAuth tokens (stored securely in UserDefaults for simplicity)
    var accessToken: String {
        get { UserDefaults.standard.string(forKey: "teams_access_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "teams_access_token") }
    }
    var refreshToken: String {
        get { UserDefaults.standard.string(forKey: "teams_refresh_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "teams_refresh_token") }
    }
    var tokenExpiry: Date {
        get { UserDefaults.standard.object(forKey: "teams_token_expiry") as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: "teams_token_expiry") }
    }

    var isTokenValid: Bool { !accessToken.isEmpty && tokenExpiry > Date().addingTimeInterval(60) }
    var isLoggedIn:   Bool { !accessToken.isEmpty }

    // MARK: - Polling
    @Published var pollInterval: Int {
        didSet { UserDefaults.standard.set(pollInterval, forKey: "teams_poll_interval") }
    }

    // MARK: - Alerts
    @Published var alertDirectMessages: Bool {
        didSet { UserDefaults.standard.set(alertDirectMessages, forKey: "teams_alert_dm") }
    }
    @Published var alertMentions: Bool {
        didSet { UserDefaults.standard.set(alertMentions, forKey: "teams_alert_mentions") }
    }
    @Published var alertUrgent: Bool {
        didSet { UserDefaults.standard.set(alertUrgent, forKey: "teams_alert_urgent") }
    }
    @Published var alertMeetingStart: Bool {
        didSet { UserDefaults.standard.set(alertMeetingStart, forKey: "teams_alert_meeting") }
    }
    @Published var meetingAlertMinutes: Int {
        didSet { UserDefaults.standard.set(meetingAlertMinutes, forKey: "teams_meeting_minutes") }
    }

    // MARK: - Glasses
    @Published var glassesFormat: GlassesFormat {
        didSet { UserDefaults.standard.set(glassesFormat.rawValue, forKey: "teams_glasses_format") }
    }
    @Published var glassesQueryEnabled: Bool {
        didSet { UserDefaults.standard.set(glassesQueryEnabled, forKey: "teams_glasses_query") }
    }

    // MARK: - Init
    init() {
        let ud = UserDefaults.standard
        clientId             = ud.string(forKey: "teams_client_id")       ?? ""
        tenantId             = ud.string(forKey: "teams_tenant_id")       ?? "common"
        pollInterval         = ud.integer(forKey: "teams_poll_interval").nonZero  ?? 30
        alertDirectMessages  = ud.object(forKey: "teams_alert_dm")        as? Bool ?? true
        alertMentions        = ud.object(forKey: "teams_alert_mentions")  as? Bool ?? true
        alertUrgent          = ud.object(forKey: "teams_alert_urgent")    as? Bool ?? true
        alertMeetingStart    = ud.object(forKey: "teams_alert_meeting")   as? Bool ?? true
        meetingAlertMinutes  = ud.integer(forKey: "teams_meeting_minutes").nonZero ?? 5
        glassesFormat        = GlassesFormat(rawValue: ud.string(forKey: "teams_glasses_format") ?? "") ?? .compact
        glassesQueryEnabled  = ud.object(forKey: "teams_glasses_query")   as? Bool ?? true
    }

    func clearTokens() {
        accessToken  = ""
        refreshToken = ""
        tokenExpiry  = Date()
        UserDefaults.standard.removeObject(forKey: "teams_access_token")
        UserDefaults.standard.removeObject(forKey: "teams_refresh_token")
        UserDefaults.standard.removeObject(forKey: "teams_token_expiry")
    }

    // Redirect URI must match exactly what is registered in Azure
    static let redirectURI = "rokidteams://auth"

    static let scopes = [
        "User.Read",
        "Chat.Read",
        "Presence.Read",
        "Presence.Read.All",
        "Calendars.Read",
        "offline_access"
    ]
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

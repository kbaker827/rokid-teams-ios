// GlassesServer.swift — updated to use Rokid AI glasses SDK
// Previously used raw TCP sockets; now communicates over Bluetooth via RokidSDK.
//
// Setup:
//   1. pod install  (Podfile already updated)
//   2. Get credentials from https://account.rokid.com/#/setting/prove
//   3. Fill in appKey / appSecret / accessKey below

import Foundation
import RokidSDK

// ── Credentials ───────────────────────────────────────────────────────────────
private let kAppKey    = "YOUR_APP_KEY"
private let kAppSecret = "YOUR_APP_SECRET"
private let kAccessKey = "YOUR_ACCESS_KEY"

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class GlassesServer: ObservableObject {

    // Published state
    @Published var isRunning:    Bool = false
    @Published var isConnected:  Bool = false
    @Published var clientCount:  Int  = 0     // kept for UI compatibility; always 0 or 1
    @Published var nearbyDevices: [RKDevice] = []

    // Inbound callbacks (same contract as the original TCP version)
    var onRemoteQuery:     ((String) -> Void)?

    // Active paired device
    private var activeDevice: RKDevice?

    // ── SDK init ──────────────────────────────────────────────────────────────
    init() {
        RokidMobileSDK.shared.initSDK(
            appKey:    kAppKey,
            appSecret: kAppSecret,
            accessKey: kAccessKey
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error { print("[Rokid] init error: \(error)") }
                else { self?.loadPairedDevices() }
            }
        }
        RokidMobileSDK.binder.addObserver(observer: self)
    }

    // ── Device discovery ──────────────────────────────────────────────────────
    func loadPairedDevices() {
        RokidMobileSDK.device.queryDeviceList { [weak self] _, devices in
            Task { @MainActor [weak self] in
                self?.nearbyDevices = devices ?? []
                // Auto-connect to first device if only one is paired
                if let first = devices?.first { self?.connectDevice(first) }
            }
        }
    }

    func connectDevice(_ device: RKDevice) {
        activeDevice = device
        isConnected  = true
        clientCount  = 1
        isRunning    = true
        print("[Rokid] Connected to \(device.deviceName ?? "glasses")")
    }

    func disconnectDevice() {
        activeDevice = nil
        isConnected  = false
        clientCount  = 0
        isRunning    = false
    }

    // ── Public API (original method signatures preserved) ─────────────────────
    func start() {
        loadPairedDevices()
    }

    func stop() {
        activeDevice = nil
        isConnected = false
    }

    func broadcastSummary(
        chats: [TeamsChat],
        meetings: [TeamsMeeting],
        presence: UserPresence?,
        format: GlassesFormat
    ) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "summary", text: String(describing: presence), to: dev)
    }

    func broadcastMessageAlert(_ msg: TeamsMessage) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "messagealert", text: String(describing: msg), to: dev)
    }

    func broadcastMeetingAlert(_ meeting: TeamsMeeting) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "meetingalert", text: String(describing: meeting), to: dev)
    }

    func broadcastMessages(_ messages: [TeamsMessage]) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "messages", text: "", to: dev)
    }

    func broadcastMeetings(_ meetings: [TeamsMeeting]) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "meetings", text: "", to: dev)
    }

    func broadcastPresence(_ presence: UserPresence) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "presence", text: String(describing: presence), to: dev)
    }

    func broadcastStatus(_ text: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "status", text: String(describing: text), to: dev)
    }

    func broadcastError (_ text: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "error", text: String(describing: text), to: dev)
    }

    func start() {
        loadPairedDevices()
    }

    func send(_ data: Data) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "message", text: String(describing: data), to: dev)
    }

    func cancel() {
        // TODO: map to Rokid SDK call
    }
}

// ── Receive voice commands FROM the glasses ───────────────────────────────────
extension GlassesServer: SDKBinderObserver {
    nonisolated func onAsrResult(_ asr: String, device: RKDevice) {
        let cmd = asr.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            if cmd.lowercased().hasPrefix("run ") {
                self.onGlassesCommand?(String(cmd.dropFirst(4)))
            } else if cmd.lowercased().hasPrefix("ai ") {
                self.onRemoteQuery?(String(cmd.dropFirst(3)))
            } else if cmd.lowercased() == "mic" {
                self.onMicTrigger?()
            } else {
                self.onGlassesCommand?(cmd)
            }
        }
    }
}

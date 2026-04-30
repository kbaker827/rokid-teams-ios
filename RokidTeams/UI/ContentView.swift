import SwiftUI

struct ContentView: View {
    @StateObject private var settings    = SettingsStore()
    @StateObject private var authManager: TeamsAuthManager
    @StateObject private var vm:          TeamsViewModel

    init() {
        let s = SettingsStore()
        let auth = TeamsAuthManager(settings: s)
        _settings    = StateObject(wrappedValue: s)
        _authManager = StateObject(wrappedValue: auth)
        _vm          = StateObject(wrappedValue: TeamsViewModel(settings: s, authManager: auth))
    }

    var body: some View {
        TabView {
            TeamsHomeView()
                .tabItem { Label("Teams", systemImage: "bubble.left.and.bubble.right") }

            GlassesPreviewView()
                .tabItem { Label("Glasses", systemImage: "eyeglasses") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(vm)
        .environmentObject(authManager)
        .environmentObject(settings)
        .tint(.blue)
        .task {
            if vm.isSignedIn { vm.startPolling() }
        }
        .onChange(of: vm.isSignedIn) { _, signedIn in
            if signedIn { vm.startPolling() }
            else        { vm.stopPolling()  }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil || authManager.error != nil },
            set: { if !$0 { vm.errorMessage = nil; authManager.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil; authManager.error = nil }
        } message: {
            Text(vm.errorMessage ?? authManager.error ?? "")
        }
    }
}

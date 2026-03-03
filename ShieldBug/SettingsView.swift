//
//  SettingsView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ShieldBeeStore.shared

    // PIN state is read from Keychain (source of truth) and refreshed on sheet dismiss
    @State private var hasPIN = KeychainManager.hasPin
    @State private var showPINSetup  = false
    @State private var showPINChange = false
    @State private var showPINRemoveAlert = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: Deep Breath
                Section {
                    Toggle(isOn: Binding(
                        get: { store.preferences.deepBreathEnabled },
                        set: { setBreath(enabled: $0) }
                    )) {
                        Label("Deep Breath", systemImage: "lungs.fill")
                    }

                    if store.preferences.deepBreathEnabled {
                        Stepper(value: Binding(
                            get: { store.preferences.deepBreathDuration },
                            set: { setBreathDuration($0) }
                        ), in: 5...60, step: 5) {
                            Label("Duration: \(store.preferences.deepBreathDuration)s",
                                  systemImage: "timer")
                        }
                    }
                } header: {
                    Text("Deep Breath")
                } footer: {
                    Text("Shows a countdown every time you open the app. You can't change any settings until the timer runs out — giving you a moment to reconsider before disabling your blocks.")
                }

                // MARK: PIN Protection
                Section {
                    if hasPIN {
                        Button { showPINChange = true } label: {
                            Label("Change PIN", systemImage: "key.fill")
                        }
                        Button(role: .destructive) { showPINRemoveAlert = true } label: {
                            Label("Remove PIN", systemImage: "lock.open.fill")
                        }
                    } else {
                        Button { showPINSetup = true } label: {
                            Label("Set PIN Protection", systemImage: "lock.fill")
                        }
                    }
                } header: {
                    Text("PIN Protection")
                } footer: {
                    Text(hasPIN
                         ? "A PIN is required each time you open the app. Face ID or Touch ID can be used instead."
                         : "Require a PIN when opening the app. Prevents impulsive changes even if someone else has your phone.")
                }

                // MARK: Appearance
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { store.preferences.theme },
                        set: { newTheme in
                            var prefs = store.preferences
                            prefs.theme = newTheme
                            store.updatePreferences(prefs)
                        }
                    )) {
                        Label("Light",  systemImage: "sun.max").tag(AppTheme.light)
                        Label("Dark",   systemImage: "moon").tag(AppTheme.dark)
                        Label("System", systemImage: "circle.lefthalf.filled").tag(AppTheme.system)
                    }
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Image(systemName: "info.circle.fill").foregroundColor(.blue)
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "questionmark.circle.fill").foregroundColor(.gray)
                        Text("Help & Support")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                }

                // MARK: Privacy
                Section("Privacy") {
                    HStack {
                        Image(systemName: "hand.raised.fill").foregroundColor(.red)
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                    HStack {
                        Image(systemName: "doc.text.fill").foregroundColor(.blue)
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
        }
        // PIN setup sheet (no existing PIN)
        .sheet(isPresented: $showPINSetup, onDismiss: { hasPIN = KeychainManager.hasPin }) {
            PINEntryView(mode: .setup) { showPINSetup = false }
        }
        // PIN change sheet (verify current → set new)
        .sheet(isPresented: $showPINChange, onDismiss: { hasPIN = KeychainManager.hasPin }) {
            PINEntryView(mode: .change) { showPINChange = false }
        }
        // Remove PIN confirmation
        .alert("Remove PIN?", isPresented: $showPINRemoveAlert) {
            Button("Remove", role: .destructive) {
                KeychainManager.clearPin()
                hasPIN = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with access to your device will be able to change settings without a PIN.")
        }
    }

    // MARK: - Helpers

    private func setBreath(enabled: Bool) {
        var p = store.preferences
        p.deepBreathEnabled = enabled
        store.updatePreferences(p)
    }

    private func setBreathDuration(_ value: Int) {
        var p = store.preferences
        p.deepBreathDuration = value
        store.updatePreferences(p)
    }
}

#Preview {
    SettingsView()
}

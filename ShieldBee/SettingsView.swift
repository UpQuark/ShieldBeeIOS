//
//  SettingsView.swift
//  ShieldBee
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
    /// Non-nil while switching lock type — carries the type being switched to.
    @State private var pendingLockType: LockType? = nil
    @State private var showBiometricConfirm = false

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

                // MARK: App Lock
                Section {
                    Picker("Lock with", selection: Binding(
                        get: { store.preferences.lockType },
                        set: { setLockType($0) }
                    )) {
                        ForEach(LockType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    if hasPIN {
                        Button { showPINChange = true } label: {
                            Label("Change \(lockNoun)", systemImage: "key.fill")
                        }
                        Button(role: .destructive) { showPINRemoveAlert = true } label: {
                            Label("Remove \(lockNoun)", systemImage: "lock.open.fill")
                        }
                    } else {
                        Button { showPINSetup = true } label: {
                            Label("Set \(lockNoun) Protection", systemImage: "lock.fill")
                        }
                    }

                    if BiometricAuth.isAvailable {
                        Toggle(isOn: Binding(
                            get: { store.preferences.biometricUnlockEnabled },
                            set: { setBiometric(enabled: $0) }
                        )) {
                            Label("Allow \(BiometricAuth.displayName)",
                                  systemImage: BiometricAuth.iconName)
                        }
                        .disabled(!hasPIN)
                    }
                } header: {
                    Text("App Lock")
                } footer: {
                    Text(lockFooter)
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
        // Re-authenticate before turning biometric unlock on
        .sheet(isPresented: $showBiometricConfirm) {
            PINEntryView(mode: .confirm) {
                showBiometricConfirm = false
                var p = store.preferences
                p.biometricUnlockEnabled = true
                store.updatePreferences(p)
            }
        }
        // Lock-type switch (verify current in the old style → set new in the new style)
        .sheet(item: $pendingLockType, onDismiss: { hasPIN = KeychainManager.hasPin }) { target in
            PINEntryView(mode: .changeType(to: target)) { pendingLockType = nil }
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

    private var lockNoun: String { store.preferences.lockType.displayName }

    private var lockFooter: String {
        guard hasPIN else {
            return "Require a \(lockNoun.lowercased()) when opening the app. Prevents impulsive changes even if someone else has your phone. A PIN is digits only; a password accepts any characters."
        }
        let base = "A \(lockNoun.lowercased()) is required each time you open the app."
        guard BiometricAuth.isAvailable else { return base }
        return store.preferences.biometricUnlockEnabled
            ? "\(base) \(BiometricAuth.displayName) can be used instead."
            : "\(base) \(BiometricAuth.displayName) is off, so your \(lockNoun.lowercased()) is always required — that friction is the point."
    }

    /// Turning biometrics *on* re-verifies first: otherwise someone holding the unlocked phone
    /// could enable it and walk past the lock from then on. Turning it off is always safe.
    private func setBiometric(enabled: Bool) {
        if enabled {
            showBiometricConfirm = true
        } else {
            var p = store.preferences
            p.biometricUnlockEnabled = false
            store.updatePreferences(p)
        }
    }

    /// Switching type re-verifies first, because otherwise anyone holding the unlocked phone
    /// could hop to the other style and set a fresh secret without knowing the current one.
    /// With no secret set yet there is nothing to bypass, so apply it directly.
    private func setLockType(_ type: LockType) {
        guard type != store.preferences.lockType else { return }
        if hasPIN {
            pendingLockType = type
        } else {
            var p = store.preferences
            p.lockType = type
            store.updatePreferences(p)
        }
    }

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

//
//  SettingsView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var store = ShieldBeeStore.shared

    var body: some View {
        NavigationView {
            Form {
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

                Section("About") {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Help & Support")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                Section("Privacy") {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.red)
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("Terms of Service")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}

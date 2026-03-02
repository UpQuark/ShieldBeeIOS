//
//  BlockView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct BlockView: View {
    @StateObject private var vpnManager = VPNManager()
    @State private var showingPermissionAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: vpnManager.isConnected ? "shield.fill" : "shield")
                    .font(.system(size: 60))
                    .foregroundColor(vpnManager.isConnected ? .green : .red)
                    .animation(.easeInOut(duration: 0.3), value: vpnManager.isConnected)
                
                Text("VPN Setup")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("VPN-based content blocking")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Status indicator
                VStack(spacing: 10) {
                    Text("Protection Status")
                        .font(.headline)
                    
                    Text(vpnManager.isConnected ? "ACTIVE" : "INACTIVE")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(vpnManager.isConnected ? .green : .red)
                        .animation(.easeInOut(duration: 0.3), value: vpnManager.isConnected)
                    
                    Text("VPN: \(vpnManager.connectionStatus.description)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                
                // Protection toggle
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(vpnManager.isConnected ? .green : .gray)
                        Text("Enable VPN Protection")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { vpnManager.isConnected },
                            set: { newValue in
                                if vpnManager.connectionStatus == .invalid {
                                    // Request permission first
                                    vpnManager.requestVPNPermission()
                                    showingPermissionAlert = true
                                } else {
                                    var prefs = ShieldBeeStore.shared.preferences
                                    prefs.masterBlockingEnabled = newValue
                                    ShieldBeeStore.shared.updatePreferences(prefs)
                                    vpnManager.toggleVPN()
                                }
                            }
                        ))
                        .labelsHidden()
                        .disabled(vpnManager.connectionStatus == .connecting || vpnManager.connectionStatus == .disconnecting)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Setup")
            .alert("VPN Permission Required", isPresented: $showingPermissionAlert) {
                Button("OK") {
                    // User can try toggling again after granting permission
                }
            } message: {
                Text("ShieldBug needs VPN permission to block websites. Please allow VPN configuration in the system dialog, then try again.")
            }
            .alert("VPN Error", isPresented: Binding(
                get: { vpnManager.errorMessage != nil },
                set: { if !$0 { vpnManager.errorMessage = nil } }
            )) {
                Button("OK") { vpnManager.errorMessage = nil }
            } message: {
                Text(vpnManager.errorMessage ?? "")
            }
        }
    }
}

#Preview {
    BlockView()
} 
//
//  VPNManager.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import Foundation
import NetworkExtension

class VPNManager: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: NEVPNStatus = .invalid

    private var vpnManager: NETunnelProviderManager?
    
    // Static array of blocked URLs
    static let blockedURLs = [
        "reddit.com",
        "www.reddit.com",
        "old.reddit.com",
        "new.reddit.com"
    ]
    
    init() {
        setupVPN()
        observeVPNStatus()
    }
    
    private func setupVPN() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }

            if let error = error {
                print("Failed to load VPN preferences: \(error)")
            }

            if let existing = managers?.first {
                self.vpnManager = existing
                DispatchQueue.main.async { self.updateConnectionStatus() }
            } else {
                // First launch — create config and trigger permission dialog
                let manager = NETunnelProviderManager()
                manager.localizedDescription = "ShieldBug VPN"
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = "shieldbug.ShieldBug.ShieldBug-VPN-Extension"
                proto.serverAddress = "127.0.0.1"
                manager.protocolConfiguration = proto
                manager.isEnabled = true
                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        print("Failed to request VPN permission: \(saveError)")
                        return
                    }
                    self.vpnManager = manager
                    DispatchQueue.main.async { self.updateConnectionStatus() }
                }
            }
        }
    }
    
    private func observeVPNStatus() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConnectionStatus()
        }
    }
    
    private func updateConnectionStatus() {
        guard let vpnManager = vpnManager else { return }
        
        connectionStatus = vpnManager.connection.status
        isConnected = vpnManager.connection.status == .connected
    }
    
    func toggleVPN() {
        guard let vpnManager = vpnManager else { return }
        
        if vpnManager.connection.status == .connected {
            disconnectVPN()
        } else {
            connectVPN()
        }
    }
    
    private func connectVPN() {
        guard let vpnManager = vpnManager else { return }
        
        // Configure the VPN
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = "shieldbug.ShieldBug.ShieldBug-VPN-Extension"
        protocolConfiguration.serverAddress = "127.0.0.1" // Local VPN
        
        // Pass blocked URLs to the VPN extension
        protocolConfiguration.providerConfiguration = [
            "blockedURLs": VPNManager.blockedURLs
        ]
        
        vpnManager.protocolConfiguration = protocolConfiguration
        vpnManager.localizedDescription = "ShieldBug VPN"
        vpnManager.isEnabled = true
        
        // Save the configuration
        vpnManager.saveToPreferences { [weak self] error in
            if let error = error {
                print("Failed to save VPN configuration: \(error)")
                return
            }
            
            // Start the VPN connection
            do {
                try vpnManager.connection.startVPNTunnel()
            } catch {
                print("Failed to start VPN: \(error)")
            }
        }
    }
    
    private func disconnectVPN() {
        vpnManager?.connection.stopVPNTunnel()
    }
    
    func requestVPNPermission() {
        setupVPN()
    }
}

extension NEVPNStatus {
    var description: String {
        switch self {
        case .invalid:
            return "Invalid"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reasserting:
            return "Reasserting"
        case .disconnecting:
            return "Disconnecting"
        @unknown default:
            return "Unknown"
        }
    }
} 
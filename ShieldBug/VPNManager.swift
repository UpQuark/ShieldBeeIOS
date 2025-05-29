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
    
    private var vpnManager: NEVPNManager?
    
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
        vpnManager = NEVPNManager.shared()
        
        // Load existing configuration
        vpnManager?.loadFromPreferences { [weak self] error in
            if let error = error {
                print("Failed to load VPN preferences: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                self?.updateConnectionStatus()
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
        protocolConfiguration.providerBundleIdentifier = "com.shieldbug.vpn-extension" // This will need to match your extension
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
        guard let vpnManager = vpnManager else { return }
        
        vpnManager.loadFromPreferences { error in
            if let error = error {
                print("Failed to load preferences: \(error)")
                return
            }
            
            // This will trigger the permission dialog
            vpnManager.saveToPreferences { error in
                if let error = error {
                    print("Failed to save preferences: \(error)")
                } else {
                    print("VPN permission granted")
                }
            }
        }
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
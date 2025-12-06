//
//  PacketTunnelProvider.swift
//  ShieldBug VPN Extension
//
//  Created by Sam Ennis on 5/28/25.
//

import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private var blockedURLs: [String] = []
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        // Get blocked URLs from configuration
        if let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
           let providerConfig = tunnelProtocol.providerConfiguration,
           let urls = providerConfig["blockedURLs"] as? [String] {
            blockedURLs = urls
        }
        
        // Configure the tunnel network settings
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // Configure IPv4 settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = []
        tunnelNetworkSettings.ipv4Settings = ipv4Settings
        
        // Configure DNS settings to intercept DNS queries
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        // Set the tunnel network settings
        setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Start reading packets
            self.startPacketFlow()
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
    
    private func startPacketFlow() {
        // Read packets from the tunnel
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            
            var allowedPackets: [Data] = []
            var allowedProtocols: [NSNumber] = []
            
            for (index, packet) in packets.enumerated() {
                let protocolNumber = protocols[index]
                
                if self.shouldAllowPacket(packet) {
                    allowedPackets.append(packet)
                    allowedProtocols.append(protocolNumber)
                } else {
                    // Packet is blocked - don't add to allowed arrays
                    print("Blocked packet to restricted domain")
                }
            }
            
            // Write allowed packets back to the tunnel
            if !allowedPackets.isEmpty {
                self.packetFlow.writePackets(allowedPackets, withProtocols: allowedProtocols)
            }
            
            // Continue reading packets
            self.startPacketFlow()
        }
    }
    
    private func shouldAllowPacket(_ packet: Data) -> Bool {
        // Parse the packet to extract destination information
        // This is a simplified implementation - in practice, you'd need more robust packet parsing
        
        guard packet.count > 20 else { return true } // Minimum IP header size
        
        // Extract destination IP from IP header (simplified)
        let ipHeader = packet.subdata(in: 0..<20)
        
        // For HTTP/HTTPS traffic, we'd need to inspect the packet payload
        // This is a basic implementation that allows most traffic
        // In a real implementation, you'd parse TCP packets and inspect HTTP headers
        
        // For now, we'll use a simple string-based check on the packet data
        let packetString = String(data: packet, encoding: .utf8) ?? ""
        
        for blockedURL in blockedURLs {
            if packetString.contains(blockedURL) {
                return false // Block this packet
            }
        }
        
        return true // Allow packet
    }
}

// MARK: - DNS Filtering Helper
extension PacketTunnelProvider {
    
    private func isDNSQuery(_ packet: Data) -> Bool {
        // Check if this is a DNS query packet (UDP port 53)
        // This is a simplified check
        return packet.count > 28 // Minimum size for IP + UDP + DNS header
    }
    
    private func shouldBlockDNSQuery(_ packet: Data) -> Bool {
        // Parse DNS query and check against blocked domains
        // This would require proper DNS packet parsing
        let packetString = String(data: packet, encoding: .utf8) ?? ""
        
        for blockedURL in blockedURLs {
            if packetString.contains(blockedURL) {
                return true
            }
        }
        
        return false
    }
} 
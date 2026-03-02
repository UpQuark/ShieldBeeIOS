//
//  PacketTunnelProvider.swift
//  ShieldBug VPN Extension
//
//  Created by Sam Ennis on 5/29/25.
//

import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var blockedURLs: [String] = []

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {

        // Get blocked URLs from configuration
        if let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
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
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            var allowedPackets: [Data] = []
            var allowedProtocols: [NSNumber] = []

            for (index, packet) in packets.enumerated() {
                let proto = protocols[index]
                if self.shouldAllowPacket(packet) {
                    allowedPackets.append(packet)
                    allowedProtocols.append(proto)
                } else {
                    print("Blocked packet to restricted domain")
                }
            }

            if !allowedPackets.isEmpty {
                self.packetFlow.writePackets(allowedPackets, withProtocols: allowedProtocols)
            }

            self.startPacketFlow()
        }
    }

    private func shouldAllowPacket(_ packet: Data) -> Bool {
        guard packet.count > 20 else { return true }

        let packetString = String(data: packet, encoding: .utf8) ?? ""
        for blockedURL in blockedURLs {
            if packetString.contains(blockedURL) {
                return false
            }
        }
        return true
    }
}

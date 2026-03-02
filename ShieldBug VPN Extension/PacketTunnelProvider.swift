//
//  PacketTunnelProvider.swift
//  ShieldBug VPN Extension
//
//  Created by Sam Ennis on 5/29/25.
//
//  Architecture: DNS-intercept tunnel.
//  - Routes ONLY DNS queries (to a virtual DNS address) through the tunnel.
//  - All other traffic bypasses the tunnel entirely.
//  - Blocked domains receive an NXDOMAIN response.
//  - All other domains are forwarded to a real upstream DNS server and relayed back.

import NetworkExtension
import Network

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var blockedDomains: Set<String> = []

    // Virtual addresses used inside the tunnel
    private let tunnelAddress  = "192.0.2.1"   // this device's tunnel interface address
    private let virtualDNS     = "192.0.2.2"   // fake DNS server — only address routed through tunnel
    private let upstreamDNS    = "8.8.8.8"     // real DNS we forward non-blocked queries to

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        if let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           let urls = cfg["blockedURLs"] as? [String] {
            blockedDomains = Set(urls.map { $0.lowercased() })
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Only DNS goes through the tunnel — everything else uses the normal internet path
        settings.dnsSettings = NEDNSSettings(servers: [virtualDNS])

        let ipv4 = NEIPv4Settings(addresses: [tunnelAddress], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: virtualDNS, subnetMask: "255.255.255.255")]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error { completionHandler(error); return }
            self?.readNextPacketBatch()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }

    // MARK: - Packet loop

    private func readNextPacketBatch() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            for (i, packet) in packets.enumerated() {
                self.handlePacket(packet, version: protocols[i])
            }
            self.readNextPacketBatch()
        }
    }

    private func handlePacket(_ packet: Data, version: NSNumber) {
        guard let info = parseDNSQuery(from: packet) else { return }

        if isDomainBlocked(info.domain) {
            replyNXDOMAIN(info: info, version: version)
        } else {
            forwardToUpstream(info: info, version: version)
        }
    }

    // MARK: - Domain check

    private func isDomainBlocked(_ domain: String) -> Bool {
        let lower = domain.lowercased()
        for blocked in blockedDomains {
            if lower == blocked || lower.hasSuffix(".\(blocked)") {
                return true
            }
        }
        return false
    }

    // MARK: - NXDOMAIN reply

    private func replyNXDOMAIN(info: DNSQueryInfo, version: NSNumber) {
        var dns = Data()
        dns.append(UInt8(info.transactionID >> 8))
        dns.append(UInt8(info.transactionID & 0xFF))
        dns.append(0x81); dns.append(0x83)  // flags: response + NXDOMAIN
        dns.append(0x00); dns.append(0x01)  // 1 question
        dns.append(0x00); dns.append(0x00)  // 0 answers
        dns.append(0x00); dns.append(0x00)  // 0 authority
        dns.append(0x00); dns.append(0x00)  // 0 additional
        dns.append(contentsOf: info.questionSection)

        let pkt = buildIPUDP(payload: dns, srcIP: virtualDNS, dstIP: tunnelAddress,
                             srcPort: 53, dstPort: info.srcPort)
        packetFlow.writePackets([pkt], withProtocols: [version])
    }

    // MARK: - Upstream forwarding

    private func forwardToUpstream(info: DNSQueryInfo, version: NSNumber) {
        let conn = NWConnection(host: NWEndpoint.Host(upstreamDNS), port: 53, using: .udp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                conn.send(content: info.dnsPayload, completion: .contentProcessed { _ in })
                conn.receiveMessage { data, _, _, _ in
                    if let data = data {
                        let pkt = self.buildIPUDP(payload: data, srcIP: self.virtualDNS,
                                                  dstIP: self.tunnelAddress, srcPort: 53,
                                                  dstPort: info.srcPort)
                        self.packetFlow.writePackets([pkt], withProtocols: [version])
                    }
                    conn.cancel()
                }
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: .global())
    }

    // MARK: - DNS query parsing

    private struct DNSQueryInfo {
        let transactionID: UInt16
        let domain: String
        let questionSection: Data  // QNAME + QTYPE + QCLASS (echoed in responses)
        let srcPort: UInt16
        let dnsPayload: Data       // full DNS payload (forwarded as-is to upstream)
    }

    private func parseDNSQuery(from packet: Data) -> DNSQueryInfo? {
        let b = [UInt8](packet)
        guard b.count >= 28 else { return nil }

        // IPv4 only
        guard (b[0] >> 4) == 4 else { return nil }
        let ihl = Int(b[0] & 0x0F) * 4

        // UDP only
        guard b[9] == 17, b.count >= ihl + 8 else { return nil }

        let srcPort = (UInt16(b[ihl]) << 8) | UInt16(b[ihl + 1])
        let dstPort = (UInt16(b[ihl + 2]) << 8) | UInt16(b[ihl + 3])
        guard dstPort == 53 else { return nil }

        let dnsOffset = ihl + 8
        guard b.count >= dnsOffset + 12 else { return nil }

        let dns = Array(b[dnsOffset...])

        // Only handle queries (QR bit = 0)
        guard (dns[2] & 0x80) == 0 else { return nil }

        let transactionID = (UInt16(dns[0]) << 8) | UInt16(dns[1])

        // Parse QNAME starting at offset 12
        var idx = 12
        let qnameStart = idx
        var labels: [String] = []

        while idx < dns.count {
            let len = Int(dns[idx])
            if len == 0 { idx += 1; break }
            idx += 1
            guard idx + len <= dns.count else { return nil }
            if let label = String(bytes: dns[idx..<(idx + len)], encoding: .utf8) {
                labels.append(label)
            }
            idx += len
        }

        // Need QTYPE + QCLASS (4 bytes) after QNAME
        guard idx + 4 <= dns.count else { return nil }
        let questionSection = Data(dns[qnameStart..<(idx + 4)])

        return DNSQueryInfo(
            transactionID: transactionID,
            domain: labels.joined(separator: "."),
            questionSection: questionSection,
            srcPort: srcPort,
            dnsPayload: Data(dns)
        )
    }

    // MARK: - IP/UDP packet builder

    private func buildIPUDP(payload: Data, srcIP: String, dstIP: String,
                            srcPort: UInt16, dstPort: UInt16) -> Data {
        let src = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dst = dstIP.split(separator: ".").compactMap { UInt8($0) }
        guard src.count == 4, dst.count == 4 else { return Data() }

        let udpLen = UInt16(8 + payload.count)
        var udp = Data()
        udp.append(UInt8(srcPort >> 8)); udp.append(UInt8(srcPort & 0xFF))
        udp.append(UInt8(dstPort >> 8)); udp.append(UInt8(dstPort & 0xFF))
        udp.append(UInt8(udpLen >> 8));  udp.append(UInt8(udpLen & 0xFF))
        udp.append(0x00); udp.append(0x00)  // checksum — zero is valid for IPv4 UDP
        udp.append(contentsOf: payload)

        let totalLen = UInt16(20 + udp.count)
        var ip = Data(count: 20)
        ip[0] = 0x45; ip[1] = 0x00
        ip[2] = UInt8(totalLen >> 8); ip[3] = UInt8(totalLen & 0xFF)
        ip[4] = 0x00; ip[5] = 0x00
        ip[6] = 0x40; ip[7] = 0x00  // don't fragment
        ip[8] = 0x40                  // TTL = 64
        ip[9] = 0x11                  // protocol = UDP
        ip[10] = 0x00; ip[11] = 0x00  // checksum placeholder
        ip[12] = src[0]; ip[13] = src[1]; ip[14] = src[2]; ip[15] = src[3]
        ip[16] = dst[0]; ip[17] = dst[1]; ip[18] = dst[2]; ip[19] = dst[3]

        // Compute IP header checksum
        var sum: UInt32 = 0
        for j in stride(from: 0, to: 20, by: 2) {
            sum += (UInt32(ip[j]) << 8) | UInt32(ip[j + 1])
        }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        let cksum = ~UInt16(truncatingIfNeeded: sum)
        ip[10] = UInt8(cksum >> 8); ip[11] = UInt8(cksum & 0xFF)

        return ip + udp
    }
}

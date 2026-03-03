//
//  PacketTunnelProvider.swift
//  ShieldBug VPN Extension
//
//  Architecture: DNS-intercept only (split tunnel, DNS traffic only)
//
//  On startup:
//    1. Load the blocked domain list from providerConfiguration
//    2. Route ONLY the virtual DNS address through the tunnel
//    3. All other IP traffic bypasses the tunnel entirely (no performance impact)
//
//  In the tunnel:
//    - DNS query for a blocked domain (exact or any subdomain) → NXDOMAIN
//    - DNS query for an allowed domain → forwarded to 8.8.8.8 and relayed back
//
//  This approach is fully hostname-based and generic. Blocking "x.com" automatically
//  covers api.x.com, pbs.x.com, every subdomain — without enumerating IPs or CDN ranges.
//
//  Limitation: connections that were already established before the VPN connects
//  (or that survive a VPN restart via QUIC connection migration) are not affected.
//  Force-quitting an app after enabling blocking gives immediate effect.

import NetworkExtension
import Network

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var blockedDomains: Set<String> = []

    private let tunnelAddress = "192.0.2.1"
    private let virtualDNS    = "192.0.2.2"
    private let upstreamDNS   = "8.8.8.8"

    /// Well-known DoH/DoT providers. NXDOMAIN these so browsers fall back to system DNS.
    private let dohProviders: Set<String> = [
        "dns.google", "dns.cloudflare.com", "cloudflare-dns.com",
        "one.one.one.one", "doh.opendns.com", "dns.quad9.net",
        "doh.cleanbrowsing.org", "dns.nextdns.io", "dns.adguard-dns.com",
        "dns.controld.com", "freedns.controld.com",
    ]

    private static let appGroupID = "group.shieldbug.ShieldBug"

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Prefer App Group UserDefaults (always up-to-date), fall back to providerConfiguration.
        if let shared = UserDefaults(suiteName: Self.appGroupID),
           let urls = shared.stringArray(forKey: "blockedURLs"), !urls.isEmpty {
            blockedDomains = Set(urls.map { $0.lowercased() })
        } else if let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
                  let urls = cfg["blockedURLs"] as? [String] {
            blockedDomains = Set(urls.map { $0.lowercased() })
        }
        configureTunnel(completionHandler: completionHandler)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let domains = try? JSONDecoder().decode([String].self, from: messageData) {
            blockedDomains = Set(domains.map { $0.lowercased() })
        }
        completionHandler?(nil)
    }

    // MARK: - Tunnel setup

    private func configureTunnel(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Override system DNS with our virtual resolver so every DNS query
        // comes through the tunnel's packet flow.
        settings.dnsSettings = NEDNSSettings(servers: [virtualDNS])
        settings.dnsSettings?.matchDomains = [""]  // empty string = handle ALL domains

        // Only route the virtual DNS address through the tunnel.
        // All other traffic (HTTP, HTTPS, etc.) bypasses the tunnel and goes
        // directly over the native network — no proxying, no latency impact.
        let ipv4 = NEIPv4Settings(addresses: [tunnelAddress], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: virtualDNS, subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error { completionHandler(error); return }
            self?.readPackets()
            completionHandler(nil)
        }
    }

    // MARK: - Domain check

    private func isDomainBlocked(_ domain: String) -> Bool {
        let lower = domain.lowercased()
        if dohProviders.contains(where: { lower == $0 || lower.hasSuffix(".\($0)") }) { return true }
        return blockedDomains.contains { lower == $0 || lower.hasSuffix(".\($0)") }
    }

    // MARK: - Packet loop

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            for (i, packet) in packets.enumerated() {
                self.handlePacket(packet, version: protocols[i])
            }
            self.readPackets()
        }
    }

    private func handlePacket(_ packet: Data, version: NSNumber) {
        let b = [UInt8](packet)
        guard b.count >= 20, (b[0] >> 4) == 4 else { return }  // IPv4 only

        let ihl   = Int(b[0] & 0x0F) * 4
        let proto = b[9]
        let dstIP = "\(b[16]).\(b[17]).\(b[18]).\(b[19])"

        // Only handle UDP packets destined for the virtual DNS address.
        guard proto == 17, dstIP == virtualDNS else { return }

        guard let info = parseDNSQuery(b, ihl: ihl) else { return }

        isDomainBlocked(info.domain)
            ? replyNXDOMAIN(info: info, version: version)
            : forwardToUpstream(info: info, version: version)
    }

    // MARK: - DNS handling

    private struct DNSInfo {
        let transactionID: UInt16
        let domain: String
        let questionSection: Data
        let srcPort: UInt16
        let dnsPayload: Data
    }

    private func parseDNSQuery(_ b: [UInt8], ihl: Int) -> DNSInfo? {
        let udpOff = ihl
        guard b.count >= udpOff + 8 else { return nil }
        let srcPort = (UInt16(b[udpOff]) << 8) | UInt16(b[udpOff + 1])
        let dstPort = (UInt16(b[udpOff + 2]) << 8) | UInt16(b[udpOff + 3])
        guard dstPort == 53 else { return nil }

        let dnsOff = udpOff + 8
        guard b.count >= dnsOff + 12 else { return nil }
        let dns = Array(b[dnsOff...])
        guard (dns[2] & 0x80) == 0 else { return nil }  // queries only

        let txID = (UInt16(dns[0]) << 8) | UInt16(dns[1])
        var idx = 12
        let qStart = idx
        var labels: [String] = []

        while idx < dns.count {
            let len = Int(dns[idx])
            if len == 0 { idx += 1; break }
            idx += 1
            guard idx + len <= dns.count else { return nil }
            if let s = String(bytes: dns[idx..<idx + len], encoding: .utf8) { labels.append(s) }
            idx += len
        }
        guard idx + 4 <= dns.count else { return nil }

        return DNSInfo(transactionID: txID, domain: labels.joined(separator: "."),
                       questionSection: Data(dns[qStart..<(idx + 4)]),
                       srcPort: srcPort, dnsPayload: Data(dns))
    }

    private func replyNXDOMAIN(info: DNSInfo, version: NSNumber) {
        var dns = Data()
        dns.append(UInt8(info.transactionID >> 8)); dns.append(UInt8(info.transactionID & 0xFF))
        dns.append(0x81); dns.append(0x83)          // response + NXDOMAIN
        dns.append(0x00); dns.append(0x01)          // 1 question
        dns.append(0x00); dns.append(0x00)          // 0 answers
        dns.append(0x00); dns.append(0x00)
        dns.append(0x00); dns.append(0x00)
        dns.append(contentsOf: info.questionSection)

        let udp = buildUDP(payload: dns, srcPort: 53, dstPort: info.srcPort)
        let pkt = buildIP(payload: udp, srcIP: virtualDNS, dstIP: tunnelAddress, proto: 17)
        packetFlow.writePackets([pkt], withProtocols: [version])
    }

    private func forwardToUpstream(info: DNSInfo, version: NSNumber) {
        let conn = NWConnection(host: NWEndpoint.Host(upstreamDNS), port: 53, using: .udp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                conn.send(content: info.dnsPayload, completion: .contentProcessed { _ in })
                conn.receiveMessage { data, _, _, _ in
                    if let data = data {
                        let udp = self.buildUDP(payload: data, srcPort: 53, dstPort: info.srcPort)
                        let pkt = self.buildIP(payload: udp, srcIP: self.virtualDNS,
                                               dstIP: self.tunnelAddress, proto: 17)
                        self.packetFlow.writePackets([pkt], withProtocols: [version])
                    }
                    conn.cancel()
                }
            } else if case .failed = state { conn.cancel() }
        }
        conn.start(queue: .global())
    }

    // MARK: - Packet builders

    private func buildUDP(payload: Data, srcPort: UInt16, dstPort: UInt16) -> Data {
        let len = UInt16(8 + payload.count)
        var udp = Data()
        udp.append(UInt8(srcPort >> 8)); udp.append(UInt8(srcPort & 0xFF))
        udp.append(UInt8(dstPort >> 8)); udp.append(UInt8(dstPort & 0xFF))
        udp.append(UInt8(len >> 8));     udp.append(UInt8(len & 0xFF))
        udp.append(0x00); udp.append(0x00)  // checksum optional in IPv4
        udp.append(contentsOf: payload)
        return udp
    }

    private func buildIP(payload: Data, srcIP: String, dstIP: String, proto: UInt8) -> Data {
        let src = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dst = dstIP.split(separator: ".").compactMap { UInt8($0) }
        guard src.count == 4, dst.count == 4 else { return Data() }

        let total = UInt16(20 + payload.count)
        var ip = Data(count: 20)
        ip[0] = 0x45; ip[1] = 0x00
        ip[2] = UInt8(total >> 8); ip[3] = UInt8(total & 0xFF)
        ip[6] = 0x40                    // don't fragment
        ip[8] = 0x40; ip[9] = proto     // TTL=64
        ip[12] = src[0]; ip[13] = src[1]; ip[14] = src[2]; ip[15] = src[3]
        ip[16] = dst[0]; ip[17] = dst[1]; ip[18] = dst[2]; ip[19] = dst[3]
        let ck = checksum([UInt8](ip))
        ip[10] = UInt8(ck >> 8); ip[11] = UInt8(ck & 0xFF)
        return ip + payload
    }

    private func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        for i in stride(from: 0, to: bytes.count & ~1, by: 2) {
            sum += (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
        }
        if bytes.count % 2 != 0 { sum += UInt32(bytes.last!) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}

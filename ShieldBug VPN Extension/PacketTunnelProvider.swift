//
//  PacketTunnelProvider.swift
//  ShieldBug VPN Extension
//
//  Architecture: Split-tunnel + IP-level blocking
//
//  On startup:
//    1. Resolve blocked domains to real IPs (extension has direct network access)
//    2. Route ONLY those IPs + a virtual DNS address through the tunnel
//    3. All other traffic bypasses the tunnel entirely
//
//  In the tunnel:
//    - TCP SYN to a blocked IP  → TCP RST  (instant connection failure, ignores DNS cache)
//    - DNS query for blocked domain → NXDOMAIN
//    - DNS query for allowed domain → forwarded to 8.8.8.8 and relayed back
//    - UDP to blocked IPs → silently dropped

import NetworkExtension
import Network
import Darwin

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var blockedDomains: Set<String> = []
    private var blockedIPs:     Set<String> = []

    private let tunnelAddress = "192.0.2.1"
    private let virtualDNS    = "192.0.2.2"
    private let upstreamDNS   = "8.8.8.8"

    // MARK: - Lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        if let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           let urls = cfg["blockedURLs"] as? [String] {
            blockedDomains = Set(urls.map { $0.lowercased() })
        }

        resolveBlockedDomains { [weak self] ips in
            guard let self = self else { return }
            self.blockedIPs = ips
            self.configureTunnel(completionHandler: completionHandler)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }

    // MARK: - Tunnel setup

    private func configureTunnel(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.dnsSettings = NEDNSSettings(servers: [virtualDNS])

        // Only route blocked IPs + virtual DNS through the tunnel
        var routes = blockedIPs.map { NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255") }
        routes.append(NEIPv4Route(destinationAddress: virtualDNS, subnetMask: "255.255.255.255"))

        let ipv4 = NEIPv4Settings(addresses: [tunnelAddress], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = routes
        settings.ipv4Settings = ipv4

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error { completionHandler(error); return }
            self?.readPackets()
            completionHandler(nil)
        }
    }

    // MARK: - IP resolution

    private func resolveBlockedDomains(completion: @escaping (Set<String>) -> Void) {
        guard !blockedDomains.isEmpty else { completion([]); return }

        var allIPs = Set<String>()
        let group = DispatchGroup()
        let lock = NSLock()

        // Resolve base domain + www. variant
        var toResolve = Set<String>()
        for domain in blockedDomains {
            toResolve.insert(domain)
            if !domain.hasPrefix("www.") { toResolve.insert("www.\(domain)") }
        }

        for domain in toResolve {
            group.enter()
            resolveHostname(domain) { ips in
                lock.lock(); allIPs.formUnion(ips); lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .global()) { completion(allIPs) }
    }

    private func resolveHostname(_ hostname: String, completion: @escaping ([String]) -> Void) {
        DispatchQueue.global().async {
            var hints = addrinfo()
            hints.ai_family   = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?

            guard getaddrinfo(hostname, nil, &hints, &result) == 0, let head = result else {
                completion([]); return
            }
            defer { freeaddrinfo(head) }

            var addresses: [String] = []
            var cur: UnsafeMutablePointer<addrinfo>? = head
            while let ptr = cur {
                if ptr.pointee.ai_family == AF_INET {
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    ptr.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        var addr = sin.pointee.sin_addr
                        inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                    }
                    let ip = String(cString: buf)
                    if !ip.isEmpty && !addresses.contains(ip) { addresses.append(ip) }
                }
                cur = ptr.pointee.ai_next
            }
            completion(addresses)
        }
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

        if proto == 17 && dstIP == virtualDNS {
            // UDP to virtual DNS → DNS interception
            guard let info = parseDNSQuery(b, ihl: ihl) else { return }
            isDomainBlocked(info.domain)
                ? replyNXDOMAIN(info: info, version: version)
                : forwardToUpstream(info: info, version: version)

        } else if proto == 6 {
            // TCP to a blocked IP → RST
            sendTCPReset(b, ihl: ihl, version: version)
        }
        // UDP to blocked IPs: silently dropped (not written back)
    }

    // MARK: - Domain check

    private func isDomainBlocked(_ domain: String) -> Bool {
        let lower = domain.lowercased()
        return blockedDomains.contains { lower == $0 || lower.hasSuffix(".\($0)") }
    }

    // MARK: - TCP RST

    private func sendTCPReset(_ b: [UInt8], ihl: Int, version: NSNumber) {
        let off = ihl
        guard b.count >= off + 20 else { return }
        let flags = b[off + 13]
        // Only respond to SYN (not SYN+ACK, not already a RST)
        guard (flags & 0x02) != 0 && (flags & 0x14) == 0 else { return }

        let srcIPStr = "\(b[12]).\(b[13]).\(b[14]).\(b[15])"
        let dstIPStr = "\(b[16]).\(b[17]).\(b[18]).\(b[19])"
        let srcPort  = (UInt16(b[off])     << 8) | UInt16(b[off + 1])
        let dstPort  = (UInt16(b[off + 2]) << 8) | UInt16(b[off + 3])
        let synSeq   = (UInt32(b[off + 4]) << 24) | (UInt32(b[off + 5]) << 16)
                     | (UInt32(b[off + 6]) << 8)  |  UInt32(b[off + 7])
        let ackNum   = synSeq + 1

        var tcp = Data(count: 20)
        tcp[0]  = UInt8(dstPort >> 8);    tcp[1]  = UInt8(dstPort & 0xFF)   // src port
        tcp[2]  = UInt8(srcPort >> 8);    tcp[3]  = UInt8(srcPort & 0xFF)   // dst port
        tcp[4]  = 0; tcp[5] = 0; tcp[6] = 0; tcp[7] = 0                    // seq = 0
        tcp[8]  = UInt8(ackNum >> 24);    tcp[9]  = UInt8((ackNum >> 16) & 0xFF)
        tcp[10] = UInt8((ackNum >> 8) & 0xFF); tcp[11] = UInt8(ackNum & 0xFF)
        tcp[12] = 0x50                          // data offset = 5 (20 bytes)
        tcp[13] = 0x14                          // RST | ACK
        tcp[14] = 0; tcp[15] = 0               // window = 0
        tcp[16] = 0; tcp[17] = 0               // checksum placeholder
        tcp[18] = 0; tcp[19] = 0               // urgent pointer

        let ck = tcpChecksum(srcIP: dstIPStr, dstIP: srcIPStr, tcp: tcp)
        tcp[16] = UInt8(ck >> 8); tcp[17] = UInt8(ck & 0xFF)

        let pkt = buildIP(payload: tcp, srcIP: dstIPStr, dstIP: srcIPStr, proto: 6)
        packetFlow.writePackets([pkt], withProtocols: [version])
    }

    private func tcpChecksum(srcIP: String, dstIP: String, tcp: Data) -> UInt16 {
        let src = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dst = dstIP.split(separator: ".").compactMap { UInt8($0) }
        guard src.count == 4, dst.count == 4 else { return 0 }

        var pseudo = Data()
        pseudo.append(contentsOf: src)
        pseudo.append(contentsOf: dst)
        pseudo.append(0x00); pseudo.append(0x06)
        let len = UInt16(tcp.count)
        pseudo.append(UInt8(len >> 8)); pseudo.append(UInt8(len & 0xFF))
        pseudo.append(contentsOf: tcp)
        if pseudo.count % 2 != 0 { pseudo.append(0x00) }

        return checksum([UInt8](pseudo))
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

# ShieldBug VPN Setup Instructions

## Overview
ShieldBug now includes VPN functionality to block specific websites (like reddit.com) using iOS NetworkExtension framework. This requires additional Xcode project configuration.

## Required Xcode Project Setup

### 1. Add VPN Extension Target
1. In Xcode, go to **File → New → Target**
2. Choose **Network Extension**
3. Select **Packet Tunnel Provider**
4. Name it "ShieldBug VPN Extension"
5. Set Bundle Identifier to: `com.shieldbug.vpn-extension`

### 2. Configure Main App Target
1. Select your main app target in Xcode
2. Go to **Signing & Capabilities**
3. Click **+ Capability** and add:
   - **Network Extensions**
   - **App Groups** (create group: `group.com.shieldbug.shared`)
4. Set the entitlements file to `ShieldBug/ShieldBug.entitlements`

### 3. Configure VPN Extension Target
1. Select the VPN extension target
2. Go to **Signing & Capabilities**
3. Add the same capabilities:
   - **Network Extensions**
   - **App Groups** (same group: `group.com.shieldbug.shared`)
4. Set the entitlements file to `ShieldBug/VPNExtension.entitlements`
5. Set Info.plist to `ShieldBug/VPNExtension-Info.plist`

### 4. Add Source Files to Targets
1. Add `PacketTunnelProvider.swift` to the VPN Extension target only
2. Add `VPNManager.swift` to the Main App target only
3. Ensure all other Swift files are in the Main App target

### 5. Update Bundle Identifiers
Make sure the bundle identifier in `VPNManager.swift` matches your extension:
```swift
protocolConfiguration.providerBundleIdentifier = "com.shieldbug.vpn-extension"
```

### 6. Apple Developer Account Requirements
- **Paid Apple Developer Account** is required for VPN functionality
- VPN apps cannot be tested in the iOS Simulator
- Must test on a physical iOS device
- App must be code signed with a valid provisioning profile

## How It Works

### Blocked URLs
The VPN blocks these domains (defined in `VPNManager.swift`):
- reddit.com
- www.reddit.com
- old.reddit.com
- new.reddit.com

### User Flow
1. User toggles "Enable VPN Protection" in the Block tab
2. iOS prompts for VPN permission (first time only)
3. VPN connects and routes all traffic through the packet tunnel
4. PacketTunnelProvider filters packets and blocks requests to blocked domains
5. User sees "ACTIVE" status when VPN is connected

### Technical Implementation
- Uses `NEPacketTunnelProvider` for packet-level filtering
- Intercepts network traffic and blocks packets to specified domains
- Maintains local VPN connection (127.0.0.1) for filtering
- Uses DNS settings to intercept domain resolution

## Testing
1. Build and run on a physical iOS device (VPN doesn't work in simulator)
2. Toggle the protection switch in the Block tab
3. Grant VPN permission when prompted
4. Try accessing reddit.com in Safari - it should be blocked
5. Check the VPN status in iOS Settings → VPN

## Troubleshooting
- Ensure all bundle identifiers match between targets and code
- Verify entitlements are properly configured
- Check that you have a paid Apple Developer account
- Make sure you're testing on a physical device, not simulator
- Review Xcode console for VPN-related error messages

## Security Note
This implementation provides basic URL blocking. For production use, consider:
- More robust packet parsing
- HTTPS traffic inspection (requires additional certificates)
- DNS-over-HTTPS blocking
- Whitelist/blacklist management
- User configuration options 
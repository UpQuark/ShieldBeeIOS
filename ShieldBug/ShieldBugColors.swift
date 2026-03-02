//
//  ShieldBugColors.swift
//  ShieldBug
//
//  Brand color palette derived from the ShieldBug Chrome extension MUI theme.
//

import SwiftUI

extension Color {
    // Primary brand orange — matches MUI primary #ff9800
    static let sbOrange     = Color(red: 1.000, green: 0.596, blue: 0.000)

    // Dark mode backgrounds — warm near-blacks from MUI dark palette
    static let sbDarkBg     = Color(red: 0.059, green: 0.039, blue: 0.000) // #0f0a00
    static let sbDarkPaper  = Color(red: 0.137, green: 0.082, blue: 0.000) // #231500
    static let sbDarkSidebar = Color(red: 0.118, green: 0.082, blue: 0.000) // #1e1500

    // Logo gradient tones
    static let sbLogoGold    = Color(red: 0.835, green: 0.561, blue: 0.235) // #D58F3C
    static let sbLogoDeep    = Color(red: 0.792, green: 0.322, blue: 0.016) // #CA5204
    static let sbLogoVibrant = Color(red: 0.922, green: 0.459, blue: 0.000) // #EB7500
}

// MARK: - Wordmark

/// Small logo + "ShieldBee" lockup used in navigation bar leading position.
struct ShieldBeeWordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Image("ShieldBugLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text("ShieldBee")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

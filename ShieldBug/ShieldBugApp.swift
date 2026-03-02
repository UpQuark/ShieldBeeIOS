//
//  ShieldBugApp.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

@main
struct ShieldBugApp: App {
    @ObservedObject private var store = ShieldBeeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Ensure VPNManager is alive from the start so it can observe
        // blockListDidChange before the first tab is rendered.
        _ = VPNManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.sbOrange)
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ScheduleManager.shared.evaluate()
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.preferences.theme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

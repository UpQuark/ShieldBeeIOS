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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
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

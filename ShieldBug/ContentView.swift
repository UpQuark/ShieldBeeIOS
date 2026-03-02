//
//  ContentView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Warm near-black background in dark mode, matching the Chrome extension palette
            if colorScheme == .dark {
                Color.sbDarkBg.ignoresSafeArea()
            }

            TabView {
                HomeView()
                    .tabItem {
                        Image(systemName: "slash.circle.fill")
                        Text("Block")
                    }

                ScheduleView()
                    .tabItem {
                        Image(systemName: "clock.fill")
                        Text("Schedule")
                    }

                BlockView()
                    .tabItem {
                        Image(systemName: "shield.fill")
                        Text("Setup")
                    }

                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}

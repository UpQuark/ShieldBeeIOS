//
//  ContentView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "slash.circle.fill")
                    Text("Block")
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

#Preview {
    ContentView()
}

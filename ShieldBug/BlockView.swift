//
//  BlockView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct BlockView: View {
    @State private var isProtectionEnabled = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: isProtectionEnabled ? "shield.fill" : "shield")
                    .font(.system(size: 60))
                    .foregroundColor(isProtectionEnabled ? .green : .red)
                    .animation(.easeInOut(duration: 0.3), value: isProtectionEnabled)
                
                Text("Block & Protect")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Manage your security settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Status indicator
                VStack(spacing: 10) {
                    Text("Protection Status")
                        .font(.headline)
                    
                    Text(isProtectionEnabled ? "ACTIVE" : "INACTIVE")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(isProtectionEnabled ? .green : .red)
                        .animation(.easeInOut(duration: 0.3), value: isProtectionEnabled)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                
                // Protection toggle
                VStack(spacing: 15) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(isProtectionEnabled ? .green : .gray)
                        Text("Enable Protection")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $isProtectionEnabled)
                            .labelsHidden()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Block")
        }
    }
}

#Preview {
    BlockView()
} 
//
//  BlockView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct BlockView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Block & Protect")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Manage your security settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 15) {
                    Button(action: {
                        // Block action placeholder
                    }) {
                        HStack {
                            Image(systemName: "shield.lefthalf.filled")
                            Text("Enable Protection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        // Unblock action placeholder
                    }) {
                        HStack {
                            Image(systemName: "shield.slash")
                            Text("Disable Protection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
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
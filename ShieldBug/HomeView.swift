//
//  HomeView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct HomeView: View {
    @State private var blockedURLs: [String] = UserDefaults.standard.stringArray(forKey: "blockedURLs") ?? []
    @State private var showingAddURL = false
    @State private var newURL = ""

    var body: some View {
        NavigationView {
            Group {
                if blockedURLs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        Text("No blocked sites")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to add a site to block")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(blockedURLs, id: \.self) { url in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(url)
                                    .font(.body)
                            }
                        }
                        .onDelete(perform: deleteURLs)
                    }
                }
            }
            .navigationTitle("Block")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newURL = ""
                        showingAddURL = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if !blockedURLs.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .alert("Add Site", isPresented: $showingAddURL) {
                TextField("e.g. reddit.com", text: $newURL)
                Button("Add") { addURL() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a domain to block (e.g. reddit.com)")
            }
        }
    }

    private func addURL() {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !blockedURLs.contains(trimmed) else { return }
        blockedURLs.append(trimmed)
        save()
    }

    private func deleteURLs(at offsets: IndexSet) {
        blockedURLs.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        UserDefaults.standard.set(blockedURLs, forKey: "blockedURLs")
    }
}

#Preview {
    HomeView()
}

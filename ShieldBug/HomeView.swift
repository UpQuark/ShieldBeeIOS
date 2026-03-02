//
//  HomeView.swift
//  ShieldBug
//
//  Created by Sam Ennis on 5/28/25.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject private var store = ShieldBeeStore.shared
    @State private var showingAddURL = false
    @State private var newURL = ""

    var body: some View {
        NavigationView {
            List {
                Section("Blocked Sites") {
                    if store.blockedSites.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "slash.circle")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No blocked sites")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Tap + to add a site")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.blockedSites) { site in
                            HStack {
                                Text(site.domain)
                                    .foregroundColor(site.isEnabled ? .primary : .secondary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { site.isEnabled },
                                    set: { store.setBlockedSiteEnabled(site.id, enabled: $0) }
                                ))
                                .labelsHidden()
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                store.removeBlockedSite(id: store.blockedSites[idx].id)
                            }
                        }
                    }
                }

                Section("Categories") {
                    ForEach(BlockCategoryType.allCases) { type in
                        CategoryRow(type: type)
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
                if !store.blockedSites.isEmpty {
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
        guard let domain = parseDomain(newURL) else { return }
        guard !store.blockedSites.contains(where: { $0.domain == domain }) else { return }
        store.addBlockedSite(domain: domain)
        newURL = ""
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let type: BlockCategoryType
    @ObservedObject private var store = ShieldBeeStore.shared
    @State private var expanded = false
    @State private var showingAddDomain = false
    @State private var newDomain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                Text(type.displayName)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Toggle("", isOn: Binding(
                    get: { store.isEnabled(type) },
                    set: { store.setCategoryEnabled(type, enabled: $0) }
                ))
                .labelsHidden()
            }

            if expanded {
                let builtIn  = CategoryDomains.domains(for: type)
                let custom   = store.customDomains(for: type)

                // Built-in domain preview
                Text(builtIn.prefix(6).joined(separator: "  ·  "))
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.leading, 32)
                    .transition(.opacity)

                // Custom domains with remove button
                ForEach(custom, id: \.self) { domain in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                            .foregroundColor(iconColor.opacity(0.7))
                        Text(domain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            store.removeCustomDomain(domain, from: type)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(.systemGray3))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 32)
                }

                // Subtle add button
                Button {
                    newDomain = ""
                    showingAddDomain = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.caption2)
                        Text("Add custom domain")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.leading, 32)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .alert("Add to \(type.displayName)", isPresented: $showingAddDomain) {
            TextField("e.g. example.com", text: $newDomain)
            Button("Add") { addDomain() }
            Button("Cancel", role: .cancel) { newDomain = "" }
        } message: {
            Text("Enter a domain to add to this category")
        }
    }

    private func addDomain() {
        guard let domain = parseDomain(newDomain) else { return }
        store.addCustomDomain(domain, to: type)
        newDomain = ""
    }

    private var iconName: String {
        switch type {
        case .socialMedia:    return "person.2.fill"
        case .news:           return "newspaper.fill"
        case .shopping:       return "cart.fill"
        case .videoStreaming:  return "play.rectangle.fill"
        case .gambling:       return "suit.spade.fill"
        }
    }

    private var iconColor: Color {
        switch type {
        case .socialMedia:    return .blue
        case .news:           return .orange
        case .shopping:       return .green
        case .videoStreaming:  return .red
        case .gambling:       return .purple
        }
    }
}

// MARK: - Shared helpers

/// Strips scheme and path, lowercases, and validates the input looks like a domain.
fileprivate func parseDomain(_ input: String) -> String? {
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for scheme in ["https://", "http://"] {
        if s.hasPrefix(scheme) { s = String(s.dropFirst(scheme.count)) }
    }
    if let slash = s.firstIndex(of: "/") { s = String(s[s.startIndex..<slash]) }
    if let q = s.firstIndex(of: "?") { s = String(s[s.startIndex..<q]) }
    guard !s.isEmpty, s.contains("."), !s.contains(" ") else { return nil }
    return s
}

#Preview {
    HomeView()
}

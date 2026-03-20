import SwiftUI

/// Main layout: sidebar + detail
struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab: SidebarTab = .chats

    enum SidebarTab: String, CaseIterable {
        case chats = "Chats"
        case contacts = "Contacts"
        case bulletins = "Bulletins"
        case connection = "Connection"
        case identity = "Identity"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.connectionState.color)
                        .frame(width: 8, height: 8)
                    Text(state.connectionState.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("| \(state.queryCount)q")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if state.useRelayHTTP {
                        Text("| HTTP")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    if state.devMode {
                        Text("| DEV")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .onAppear {
            if !state.hasIdentity { selectedTab = .identity }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: iconFor(tab))
                    .badge(badgeFor(tab))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .chats: ChatListView()
        case .contacts: ContactsPanel()
        case .bulletins: BulletinPanel()
        case .connection: ConnectionPanel()
        case .identity: IdentityPanel()
        }
    }

    private func iconFor(_ tab: SidebarTab) -> String {
        switch tab {
        case .chats: return "bubble.left.and.bubble.right"
        case .contacts: return "person.2"
        case .bulletins: return "megaphone"
        case .connection: return "antenna.radiowaves.left.and.right"
        case .identity: return "person.crop.circle"
        }
    }

    private func badgeFor(_ tab: SidebarTab) -> Int {
        if tab == .chats { return state.unreadCounts.values.reduce(0, +) }
        if tab == .bulletins { return state.bulletins.isEmpty ? 0 : 0 }
        return 0
    }
}

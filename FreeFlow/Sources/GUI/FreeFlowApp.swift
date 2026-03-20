import SwiftUI
import FreeFlowCore

@main
struct FreeFlowApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsPanel()
                .environmentObject(appState)
                .frame(width: 500, height: 450)
        }
    }
}

import AppKit
import SwiftUI

@MainActor
final class WorklogAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ChoskyWorklogApp: App {
    @NSApplicationDelegateAdaptor(WorklogAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup(ProductConfig.name, id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.sessions)
                .environmentObject(model.activityWatch)
                .environmentObject(model.sharing)
                .frame(minWidth: 980, minHeight: 650)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Abrir carpeta de datos") {
                    NSWorkspace.shared.open(ProductConfig.appSupportURL)
                }
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(model.sessions)
                .environmentObject(model.activityWatch)
                .environmentObject(model.sharing)
        } label: {
            Label(
                menuBarLabel,
                systemImage: menuBarSymbol
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.sessions)
                .environmentObject(model.activityWatch)
        }
    }

    private var menuBarLabel: String {
        model.sessions.activeSession?.state.label ?? ProductConfig.name
    }

    private var menuBarSymbol: String {
        switch model.sessions.activeSession?.state {
        case .running: "record.circle"
        case .manuallyPaused: "pause.circle"
        case .privacyPaused: "eye.slash.circle"
        case .afk: "moon.circle"
        case .sleeping, .recovering: "arrow.clockwise.circle"
        case nil, .prepared, .finished, .corrected, .archived: "clock"
        }
    }
}
